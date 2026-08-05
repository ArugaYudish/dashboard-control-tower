{{
    config(
        materialized='table',
        schema='spx'
    )
}}

WITH 
-- 1. STAGING SNAPSHOT: CARI upd_date TERAKHIR PER DISTRIBUTOR & PERIODE
cte_cb_snapshot AS (
    SELECT 
        st.distributor_id,
        st.sls_id,
        st.cust_id,
        st.periode AS period,
        st.tahun AS year,
        st.channel_id,
        st.salesforce_id,
        st.upd_date,
        
        MAX(st.upd_date) OVER (
            PARTITION BY st.distributor_id, st.tahun, st.periode
        ) AS upd_date_terakhir

    FROM raw_ficom_m3.v_fcustsls_staging st
    WHERE st.flag_aktif = 'Y'
      AND st.salesforce_id NOT IN ('999', '116', '213', '222')
),

-- 2. DEDUP & JOIN KE TABEL MASTER HIRARKI
cte_cb_filtered AS (
    SELECT DISTINCT ON (s.distributor_id, s.cust_id, s.sls_id, s.year, s.period)
        a.sd_id,
        a.sd_nm,
        a.grsm_id,
        a.grsm_nm,
        a.rsm_id,
        a.rsm_nm,
        a.ss_id,
        a.ss_nm,
        a.sls_id,
        ms.sls_nm,
        c.distributor_id,
        md.distributor_nm,
        e.group_channel_id,
        e.group_channel_nm,
        e.channel_id,
        e.channel_nm,
        s.period,
        s.year,
        s.salesforce_id,
        mmgs.salesforce_nm,
        mmgs.gsalesforce_id,
        mmgs.gsalesforce_nm,
        s.cust_id
    FROM raw_ficom_m3.v_salesman_hierarchy a
    JOIN raw_ficom_m3.m_employee b
        ON a.ss_id = b.emp_id
    JOIN raw_ficom_m3.m_salesman_spv c
        ON c.sls_id = a.sls_id AND c.distributor_id = a.distributor_id
    JOIN cte_cb_snapshot s
        ON s.distributor_id = c.distributor_id AND s.sls_id = c.sls_id
    JOIN raw_ficom_m3.m_group_channels e
        ON s.channel_id = e.channel_id
    LEFT JOIN raw_ficom_m3.m_mapping_group_salesforce mmgs
        ON s.salesforce_id::text = mmgs.salesforce_id::text
    LEFT JOIN raw_ficom_m3.m_salesman ms
        ON c.distributor_id = ms.distributor_id AND c.sls_id = ms.sls_id
    LEFT JOIN raw_ficom_m3.m_distributor md
        ON c.distributor_id = md.distributor_id
    WHERE b.terminate_date IS NULL
      AND s.upd_date = s.upd_date_terakhir
    ORDER BY s.distributor_id, s.cust_id, s.sls_id, s.year, s.period DESC
),

-- 3. AGGREGATE CB UNIK PER HIERARCHY & PERIODE
cte_cb AS (
    SELECT
        sd_id,
        sd_nm,
        grsm_id,
        grsm_nm,
        rsm_id,
        rsm_nm,
        ss_id,
        ss_nm,
        sls_id,
        sls_nm,
        distributor_id,
        distributor_nm,
        group_channel_id,
        group_channel_nm,
        channel_id,
        channel_nm,
        salesforce_id,
        salesforce_nm,
        gsalesforce_id AS group_sales_force_id,
        gsalesforce_nm AS group_sales_force_nm,
        year,
        period,

        COUNT(DISTINCT cust_id) AS cb_count
    FROM cte_cb_filtered
    GROUP BY
        sd_id,
        sd_nm,
        grsm_id,
        grsm_nm,
        rsm_id,
        rsm_nm,
        ss_id,
        ss_nm,
        sls_id,
        sls_nm,
        distributor_id,
        distributor_nm,
        group_channel_id,
        group_channel_nm,
        channel_id,
        channel_nm,
        salesforce_id,
        salesforce_nm,
        gsalesforce_id,
        gsalesforce_nm,
        year,
        period
),

-- 4. FACT GRADING (GRADE TERAKHIR TOKO DI PERIODE TERSEBUT)
cte_outlet_latest_grade AS (
    SELECT
        year,
        period,
        week,
        sd_nm,
        nsm_nm,
        grsm_nm,
        rsm_nm,
        ss_nm,
        sls_nm,
        distributor_id,
        distributor_nm,
        salesforce_id,
        salesforce_nm,
        gsalesforce_nm AS group_sales_force_nm,
        group_channel_nm,
        subbrand_nm,
        pcode,
        pcode_nm,
        outlet_id,
        grade,
        is_ec_avis,
        is_ec_display,
        is_ec_transaction,
        ROW_NUMBER() OVER (
            PARTITION BY year, period, distributor_id, outlet_id 
            ORDER BY report_date DESC
        ) AS rn
    FROM {{ ref('gold_grading_dashboard') }}
    WHERE salesforce_id NOT IN ('999', '116', '213', '222')
),

cte_grading_summary AS (
    SELECT
        year,
        period,
        week,
        sd_nm,
        nsm_nm,
        grsm_nm,
        rsm_nm,
        ss_nm,
        sls_nm,
        distributor_id,
        distributor_nm,
        salesforce_id,
        salesforce_nm,
        group_sales_force_nm,
        group_channel_nm,
        subbrand_nm,
        pcode,
        pcode_nm,

        COUNT(DISTINCT outlet_id) AS oa_count,
        COUNT(CASE WHEN grade = 'A' THEN 1 END) AS grade_a_count,
        COUNT(CASE WHEN grade = 'B' THEN 1 END) AS grade_b_count,
        COUNT(CASE WHEN grade = 'C' THEN 1 END) AS grade_c_count,
        COUNT(CASE WHEN grade NOT IN ('A', 'B', 'C') OR grade IS NULL THEN 1 END) AS non_grade_count,

        MAX(is_ec_avis) AS is_ec_avis,
        MAX(is_ec_display) AS is_ec_display,
        MAX(is_ec_transaction) AS is_ec_transaction
    FROM cte_outlet_latest_grade
    WHERE rn = 1
    GROUP BY
        year, period, week, sd_nm, nsm_nm, grsm_nm, rsm_nm, ss_nm, sls_nm,
        distributor_id, distributor_nm, salesforce_id, salesforce_nm,
        group_sales_force_nm, group_channel_nm, subbrand_nm, pcode, pcode_nm
)

-- 5. COMBINE SUMMARY (FULL JOIN)
SELECT
    COALESCE(g.year, c.year) AS year,
    COALESCE(g.period, c.period) AS period,
    COALESCE(g.week, 0) AS week,
    
    COALESCE(g.sd_nm, c.sd_nm) AS sd_nm,
    g.nsm_nm AS nsm_nm,
    COALESCE(g.grsm_nm, c.grsm_nm) AS grsm_nm,
    COALESCE(g.rsm_nm, c.rsm_nm) AS rsm_nm,
    COALESCE(g.ss_nm, c.ss_nm) AS ss_nm,
    COALESCE(g.sls_nm, c.sls_nm, '') AS sls_nm,
    
    COALESCE(g.distributor_id, c.distributor_id) AS distributor_id,
    COALESCE(g.distributor_nm, c.distributor_nm) AS distributor_nm,
    COALESCE(g.salesforce_id, c.salesforce_id) AS salesforce_id,
    COALESCE(g.salesforce_nm, c.salesforce_nm) AS salesforce_nm,
    COALESCE(g.group_sales_force_nm, c.group_sales_force_nm) AS group_sales_force_nm,
    COALESCE(g.group_channel_nm, c.group_channel_nm) AS group_channel_nm,
    
    COALESCE(g.subbrand_nm, 'ALL SUBBRAND') AS subbrand_nm,
    COALESCE(g.pcode, 'ALL PCODE') AS pcode,
    COALESCE(g.pcode_nm, 'ALL PCODE') AS pcode_nm,

    COALESCE(c.cb_count, 0) AS cb_count,
    COALESCE(g.oa_count, 0) AS oa_count,
    COALESCE(g.grade_a_count, 0) AS grade_a_count,
    COALESCE(g.grade_b_count, 0) AS grade_b_count,
    COALESCE(g.grade_c_count, 0) AS grade_c_count,
    COALESCE(g.non_grade_count, 0) AS non_grade_count,

    COALESCE(g.is_ec_avis, 1) AS is_ec_avis,
    COALESCE(g.is_ec_display, 1) AS is_ec_display,
    COALESCE(g.is_ec_transaction, 1) AS is_ec_transaction

FROM cte_cb c
FULL OUTER JOIN cte_grading_summary g
    ON  c.distributor_id = g.distributor_id
    AND c.salesforce_id  = g.salesforce_id
    AND c.year           = g.year
    AND c.period         = g.period