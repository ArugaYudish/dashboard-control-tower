{{
    config(
        materialized = 'table',
        indexes = [
            {'columns': ['year', 'period', 'week']},
            {'columns': ['report_date']},
            {'columns': ['sd_id', 'nsm_id', 'grsm_id', 'rsm_id', 'ss_id']},
            {'columns': ['distributor_id', 'sls_id']},
            {'columns': ['subbrand_id']},
            {'columns': ['gsalesforce_id']},
            {'columns': ['group_channel_id']}
        ]
    )
}}

WITH 
-- 1. ANCHOR HIERARKI SALESMAN M3 (EMPLOYEE AKTIF)
active_hierarchy AS (
    SELECT DISTINCT 
        a.sd_id, a.sd_nm,
        a.nsm_id, a.nsm_nm,
        a.grsm_id, a.grsm_nm,
        a.rsm_id, a.rsm_nm,
        a.ss_id, a.ss_nm,
        c.sls_id::varchar AS sls_id,
        COALESCE(ms.sls_nm, 'UNKNOWN / UNMAPPED') AS sls_nm,
        c.distributor_id::varchar AS distributor_id,
        COALESCE(md.distributor_nm, 'UNKNOWN') AS distributor_nm
    FROM raw_ficom_m3.v_salesman_hierarchy a
    JOIN raw_ficom_m3.m_employee b ON a.ss_id = b.emp_id
    JOIN raw_ficom_m3.m_salesman_spv c ON c.sls_id = a.sls_id AND c.distributor_id = a.distributor_id
    LEFT JOIN raw_ficom_m3.m_salesman ms ON c.distributor_id = ms.distributor_id AND c.sls_id = ms.sls_id
    LEFT JOIN raw_ficom_m3.m_distributor md ON c.distributor_id = md.distributor_id
    WHERE b.terminate_date IS NULL
),

-- 2. SLICE 1: CUSTOMER BASE BULANAN (MURNI DISTRIBUTOR + CUST_ID)
cte_cb_snapshot AS (
    SELECT 
        st.distributor_id::varchar AS distributor_id,
        st.sls_id::varchar AS sls_id,
        st.cust_id::varchar AS cust_id,
        st.periode::int AS period,
        st.tahun::int AS year,
        st.upd_date,
        MAX(st.upd_date) OVER (PARTITION BY st.distributor_id::varchar, st.tahun, st.periode) AS upd_date_terakhir
    FROM raw_ficom_m3.v_fcustsls_staging st
    WHERE st.flag_aktif = 'Y'
      AND st.salesforce_id::varchar NOT IN ('999', '116', '213', '222')
),
cte_cb_dedup AS (
    SELECT DISTINCT ON (s.distributor_id, s.cust_id, s.year, s.period)
        s.distributor_id, 
        s.sls_id, 
        s.cust_id, 
        s.year, 
        s.period
    FROM cte_cb_snapshot s
    WHERE s.upd_date = s.upd_date_terakhir
    ORDER BY s.distributor_id, s.cust_id, s.year, s.period DESC, s.upd_date DESC
),
summary_cb AS (
    SELECT 
        cb.year,
        cb.period,
        0 AS week,
        NULL::date AS report_date,
        
        COALESCE(ah.sd_id, 'N/A') AS sd_id, COALESCE(ah.sd_nm, 'N/A') AS sd_nm,
        COALESCE(ah.nsm_id, 'N/A') AS nsm_id, COALESCE(ah.nsm_nm, 'N/A') AS nsm_nm,
        COALESCE(ah.grsm_id, 'N/A') AS grsm_id, COALESCE(ah.grsm_nm, 'N/A') AS grsm_nm,
        COALESCE(ah.rsm_id, 'N/A') AS rsm_id, COALESCE(ah.rsm_nm, 'N/A') AS rsm_nm,
        COALESCE(ah.ss_id, 'N/A') AS ss_id, COALESCE(ah.ss_nm, 'N/A') AS ss_nm,
        cb.sls_id, COALESCE(ah.sls_nm, 'UNKNOWN') AS sls_nm,
        cb.distributor_id, COALESCE(ah.distributor_nm, 'UNKNOWN') AS distributor_nm,
        
        'ALL_SUBBRAND' AS subbrand_id, 'ALL_SUBBRAND' AS subbrand_nm,
        'N/A' AS salesforce_id, 'N/A' AS gsalesforce_id, 'N/A' AS gsalesforce_nm,
        'N/A' AS group_channel_id, 'N/A' AS group_channel_nm,
        
        COUNT(DISTINCT cb.cust_id) AS cb_count,
        0 AS tgt_call,
        0 AS oa_count, 0 AS grade_a_count, 0 AS grade_b_count, 0 AS grade_c_count, 0 AS non_grade_count,
        0 AS total_inv_qty, 0 AS total_inv_val
    FROM cte_cb_dedup cb
    LEFT JOIN active_hierarchy ah ON cb.distributor_id = ah.distributor_id AND cb.sls_id = ah.sls_id
    GROUP BY 
        cb.year, cb.period, cb.distributor_id, cb.sls_id,
        ah.sd_id, ah.sd_nm, ah.nsm_id, ah.nsm_nm, ah.grsm_id, ah.grsm_nm, 
        ah.rsm_id, ah.rsm_nm, ah.ss_id, ah.ss_nm, ah.sls_nm, ah.distributor_nm
),

-- 3. SLICE 2: TARGET CALL HARIAN (KPL MURNI - LEFT JOIN HIERARKI)
summary_tc AS (
    SELECT 
        tc.tahun::int AS year,
        tc.periode::int AS period,
        tc.week::int AS week,
        tc.tgl::date AS report_date,
        
        COALESCE(ah.sd_id, 'N/A') AS sd_id, COALESCE(ah.sd_nm, 'N/A') AS sd_nm,
        COALESCE(ah.nsm_id, 'N/A') AS nsm_id, COALESCE(ah.nsm_nm, 'N/A') AS nsm_nm,
        COALESCE(ah.grsm_id, 'N/A') AS grsm_id, COALESCE(ah.grsm_nm, 'N/A') AS grsm_nm,
        COALESCE(ah.rsm_id, 'N/A') AS rsm_id, COALESCE(ah.rsm_nm, 'N/A') AS rsm_nm,
        COALESCE(ah.ss_id, 'N/A') AS ss_id, COALESCE(ah.ss_nm, 'N/A') AS ss_nm,
        tc.sls_id::varchar AS sls_id, COALESCE(ah.sls_nm, 'UNKNOWN') AS sls_nm,
        tc.distributor_id::varchar AS distributor_id, COALESCE(ah.distributor_nm, 'UNKNOWN') AS distributor_nm,
        
        'ALL_SUBBRAND' AS subbrand_id, 'ALL_SUBBRAND' AS subbrand_nm,
        'N/A' AS salesforce_id, 'N/A' AS gsalesforce_id, 'N/A' AS gsalesforce_nm,
        'N/A' AS group_channel_id, 'N/A' AS group_channel_nm,
        
        0 AS cb_count,
        SUM(tc.tgt_call::int) AS tgt_call,
        0 AS oa_count, 0 AS grade_a_count, 0 AS grade_b_count, 0 AS grade_c_count, 0 AS non_grade_count,
        0 AS total_inv_qty, 0 AS total_inv_val
    FROM raw_ficom_m3.m_nmrc_subdetail tc
    LEFT JOIN active_hierarchy ah ON tc.distributor_id::varchar = ah.distributor_id AND tc.sls_id::varchar = ah.sls_id
    GROUP BY 
        tc.tahun, tc.periode, tc.week, tc.tgl, tc.distributor_id, tc.sls_id,
        ah.sd_id, ah.sd_nm, ah.nsm_id, ah.nsm_nm, ah.grsm_id, ah.grsm_nm, 
        ah.rsm_id, ah.rsm_nm, ah.ss_id, ah.ss_nm, ah.sls_nm, ah.distributor_nm
),

-- 4. SLICE 3: ACTUAL ACTIVITY & GRADING (DARI MODEL DETAIL DASHBOARD)
summary_act AS (
    SELECT 
        g.year,
        g.period,
        g.week,
        g.report_date,
        
        g.sd_id, g.sd_nm, g.nsm_id, g.nsm_nm, g.grsm_id, g.grsm_nm, g.rsm_id, g.rsm_nm, g.ss_id, g.ss_nm,
        g.sls_id, g.sls_nm, g.distributor_id, g.distributor_nm,
        
        g.subbrand_id, g.subbrand_nm,
        g.salesforce_id, g.gsalesforce_id, g.gsalesforce_nm,
        g.group_channel_id, g.group_channel_nm,
        
        0 AS cb_count,
        0 AS tgt_call,
        COUNT(DISTINCT g.outlet_id) AS oa_count,
        COUNT(DISTINCT CASE WHEN g.grade = 'A' THEN g.outlet_id END) AS grade_a_count,
        COUNT(DISTINCT CASE WHEN g.grade = 'B' THEN g.outlet_id END) AS grade_b_count,
        COUNT(DISTINCT CASE WHEN g.grade = 'C' THEN g.outlet_id END) AS grade_c_count,
        COUNT(DISTINCT CASE WHEN g.grade NOT IN ('A', 'B', 'C') OR g.grade IS NULL THEN g.outlet_id END) AS non_grade_count,
        SUM(g.inv_qty) AS total_inv_qty,
        SUM(g.inv_val) AS total_inv_val
    FROM {{ ref('gold_grading_dashboard') }} g
    GROUP BY 
        g.year, g.period, g.week, g.report_date,
        g.sd_id, g.sd_nm, g.nsm_id, g.nsm_nm, g.grsm_id, g.grsm_nm, g.rsm_id, g.rsm_nm, g.ss_id, g.ss_nm,
        g.sls_id, g.sls_nm, g.distributor_id, g.distributor_nm,
        g.subbrand_id, g.subbrand_nm, g.salesforce_id, g.gsalesforce_id, g.gsalesforce_nm, g.group_channel_id, g.group_channel_nm
)

-- COMBINE SEMUA SLICE UNTUK BENTUK DATA MART SUMMARY
SELECT * FROM summary_cb
UNION ALL
SELECT * FROM summary_tc
UNION ALL
SELECT * FROM summary_act