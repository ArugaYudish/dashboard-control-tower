{{
    config(
        materialized='table',
        schema='spx'
    )
}}

WITH 
-- 0. MASTER HIERARKI AKTIF (FILTER UTAMA)
active_hierarchy AS (
    SELECT DISTINCT 
        a.sd_id, a.sd_nm,
        a.nsm_id, a.nsm_nm,
        a.grsm_id, a.grsm_nm,
        a.rsm_id, a.rsm_nm,
        a.ss_id, a.ss_nm,
        c.sls_id, ms.sls_nm,
        c.distributor_id, md.distributor_nm
    FROM raw_ficom_m3.v_salesman_hierarchy a
    JOIN raw_ficom_m3.m_employee b ON a.ss_id = b.emp_id
    JOIN raw_ficom_m3.m_salesman_spv c ON c.sls_id = a.sls_id AND c.distributor_id = a.distributor_id
    LEFT JOIN raw_ficom_m3.m_salesman ms ON c.distributor_id = ms.distributor_id AND c.sls_id = ms.sls_id
    LEFT JOIN raw_ficom_m3.m_distributor md ON c.distributor_id = md.distributor_id
    WHERE b.terminate_date IS NULL
),

-- 1. DATA CUSTOMER BASE (BULANAN - TAHUN 2026)
cte_cb_snapshot AS (
    SELECT 
        st.distributor_id, st.sls_id, st.cust_id,
        st.periode AS period, st.tahun AS year, st.channel_id, st.salesforce_id, st.upd_date,
        MAX(st.upd_date) OVER (PARTITION BY st.distributor_id, st.tahun, st.periode) AS upd_date_terakhir
    FROM raw_ficom_m3.v_fcustsls_staging st
    WHERE st.flag_aktif = 'Y' 
      AND st.salesforce_id NOT IN ('999', '116', '213', '222')
      AND st.tahun = 2026
),
cte_cb_filtered AS (
    SELECT DISTINCT ON (s.distributor_id, s.cust_id, s.sls_id, s.year, s.period)
        ah.sd_id, ah.sd_nm, ah.nsm_id, ah.nsm_nm, ah.grsm_id, ah.grsm_nm, ah.rsm_id, ah.rsm_nm, ah.ss_id, ah.ss_nm,
        ah.sls_id, ah.sls_nm, ah.distributor_id, ah.distributor_nm,
        e.group_channel_id, e.group_channel_nm, e.channel_id, e.channel_nm,
        s.period, s.year, s.salesforce_id, mmgs.salesforce_nm,
        mmgs.gsalesforce_id AS group_sales_force_id, mmgs.gsalesforce_nm AS group_sales_force_nm,
        s.cust_id
    FROM active_hierarchy ah
    JOIN cte_cb_snapshot s ON s.distributor_id = ah.distributor_id AND s.sls_id = ah.sls_id
    JOIN raw_ficom_m3.m_group_channels e ON s.channel_id = e.channel_id
    LEFT JOIN raw_ficom_m3.m_mapping_group_salesforce mmgs ON s.salesforce_id::text = mmgs.salesforce_id::text
    WHERE s.upd_date = s.upd_date_terakhir
    ORDER BY s.distributor_id, s.cust_id, s.sls_id, s.year, s.period DESC
),
gold_cb_rows AS (
    SELECT
        year, period, 0 AS week, NULL::date AS report_date,
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm, ss_id, ss_nm, sls_id, sls_nm,
        distributor_id, distributor_nm, salesforce_id, salesforce_nm, group_sales_force_id, group_sales_force_nm,
        group_channel_id, group_channel_nm,
        COUNT(DISTINCT cust_id) AS cb_count,
        0 AS tgt_call, 0 AS oa_count, 0 AS grade_a_count, 0 AS grade_b_count, 0 AS grade_c_count, 0 AS non_grade_count
    FROM cte_cb_filtered
    GROUP BY year, period, sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm, ss_id, ss_nm, sls_id, sls_nm, distributor_id, distributor_nm, salesforce_id, salesforce_nm, group_sales_force_id, group_sales_force_nm, group_channel_id, group_channel_nm
),

-- 2. DATA TARGET CALL (DAILY/WEEKLY - TAHUN 2026)
gold_tc_rows AS (
    SELECT
        tc.tahun::int AS year, tc.periode::int AS period, tc.week::int AS week, tc.tgl::date AS report_date,
        ah.sd_id, ah.sd_nm, ah.nsm_id, ah.nsm_nm, ah.grsm_id, ah.grsm_nm, ah.rsm_id, ah.rsm_nm, ah.ss_id, ah.ss_nm,
        ah.sls_id, ah.sls_nm, ah.distributor_id, ah.distributor_nm,
        NULL AS salesforce_id, NULL AS salesforce_nm, NULL AS group_sales_force_id, NULL AS group_sales_force_nm,
        NULL AS group_channel_id, NULL AS group_channel_nm,
        0 AS cb_count,
        SUM(tc.tgt_call::int) AS tgt_call,
        0 AS oa_count, 0 AS grade_a_count, 0 AS grade_b_count, 0 AS grade_c_count, 0 AS non_grade_count
    FROM raw_ficom_m3.m_nmrc_subdetail tc
    JOIN active_hierarchy ah ON tc.distributor_id = ah.distributor_id AND tc.sls_id = ah.sls_id
    WHERE tc.tahun::int = 2026
    GROUP BY tc.tahun, tc.periode, tc.week, tc.tgl, ah.sd_id, ah.sd_nm, ah.nsm_id, ah.nsm_nm, ah.grsm_id, ah.grsm_nm, ah.rsm_id, ah.rsm_nm, ah.ss_id, ah.ss_nm, ah.sls_id, ah.sls_nm, ah.distributor_id, ah.distributor_nm
),

-- 3. DATA FACT GRADING (DAILY/WEEKLY - TAHUN 2026)
cte_outlet_latest_grade AS (
    SELECT
        year, period, week, report_date,
        sls_id, distributor_id, salesforce_id, outlet_id, grade,
        ROW_NUMBER() OVER (
            PARTITION BY year, period, week, report_date, distributor_id, outlet_id 
            ORDER BY report_date DESC
        ) AS rn
    FROM {{ ref('gold_grading_dashboard') }}
    WHERE salesforce_id NOT IN ('999', '116', '213', '222')
      AND year = 2026
),
gold_grading_rows AS (
    SELECT
        g.year, g.period, g.week, g.report_date,
        ah.sd_id, ah.sd_nm, ah.nsm_id, ah.nsm_nm, ah.grsm_id, ah.grsm_nm, ah.rsm_id, ah.rsm_nm, ah.ss_id, ah.ss_nm,
        ah.sls_id, ah.sls_nm, ah.distributor_id, ah.distributor_nm,
        g.salesforce_id, NULL AS salesforce_nm, NULL AS group_sales_force_id, NULL AS group_sales_force_nm,
        NULL AS group_channel_id, NULL AS group_channel_nm,
        0 AS cb_count,
        0 AS tgt_call,
        COUNT(DISTINCT g.outlet_id) AS oa_count,
        COUNT(CASE WHEN g.grade = 'A' THEN 1 END) AS grade_a_count,
        COUNT(CASE WHEN g.grade = 'B' THEN 1 END) AS grade_b_count,
        COUNT(CASE WHEN g.grade = 'C' THEN 1 END) AS grade_c_count,
        COUNT(CASE WHEN g.grade NOT IN ('A', 'B', 'C') OR g.grade IS NULL THEN 1 END) AS non_grade_count
    FROM cte_outlet_latest_grade g
    JOIN active_hierarchy ah ON g.distributor_id = ah.distributor_id AND g.sls_id = ah.sls_id
    WHERE g.rn = 1
    GROUP BY g.year, g.period, g.week, g.report_date, ah.sd_id, ah.sd_nm, ah.nsm_id, ah.nsm_nm, ah.grsm_id, ah.grsm_nm, ah.rsm_id, ah.rsm_nm, ah.ss_id, ah.ss_nm, ah.sls_id, ah.sls_nm, ah.distributor_id, ah.distributor_nm, g.salesforce_id
)

-- 4. FINAL COMBINE (UNION ALL)
SELECT * FROM gold_cb_rows
UNION ALL
SELECT * FROM gold_tc_rows
UNION ALL
SELECT * FROM gold_grading_rows