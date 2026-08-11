{{
    config(
        materialized = 'table',
        schema = 'spx',
        alias = 'gold_grading_performance_summary',
        indexes = [
            {'columns': ['year', 'period', 'week']},
            {'columns': ['report_date']},
            {'columns': ['sd_id', 'rsm_id', 'ss_id']},
            {'columns': ['distributor_id', 'sls_id', 'outlet_id']},
            {'columns': ['pcode']},
            {'columns': ['grade']}
        ]
    )
}}

WITH 
----------------------------------------------------------------------
-- 1. MASTER OUTLET & HIERARKI DARI SILVER (PEMBAGI % / DENOMINATOR)
----------------------------------------------------------------------
cte_master_outlet_silver AS (
    SELECT DISTINCT
        tahun::int AS year,
        periode::int AS period,
        gdiv_id, gdiv_nm,
        sd_id, sd_nm,
        nsm_id, nsm_nm,
        grsm_id, grsm_nm,
        rsm_id, rsm_nm,
        ss_id, ss_nm,
        distributor_id::varchar AS distributor_id,
        distributor_nm,
        cust_id::varchar AS outlet_id,
        cust_nm,
        kabupaten_name AS city -- 👈 FIX: Ambil dari kabupaten_name di Silver!
    FROM {{ ref('silver_oa_performance') }}
),

----------------------------------------------------------------------
-- 2. ALL ACTIVITY & IR PCODE DARI GOLD GRADING DASHBOARD (MAIN DATA)
----------------------------------------------------------------------
cte_grading_dashboard AS (
    SELECT 
        year::int AS year,
        period::int AS period,
        week::int AS week,
        visit_date::date AS report_date,
        visit_date,
        inv_date,
        distributor_id::varchar AS distributor_id,
        outlet_id::varchar AS outlet_id,
        sls_id::varchar AS sls_id,
        sls_nm,
        pcode::varchar AS pcode,
        pcode_nm,
        subbrand_id, subbrand_nm,
        cat_id, cat_nm,
        salesforce_id, salesforce_nm,
        gsalesforce_id, gsalesforce_nm,
        group_channel_id, group_channel_nm,
        div_id, div_nm,
        COALESCE(NULLIF(TRIM(grade), ''), 'UNGRADED / NO GRADE RECORD') AS grade,
        kode_ap,
        COALESCE(facing_qty, 0) AS facing_qty,
        COALESCE(is_ir_detected, 0) AS is_ir_detected,
        COALESCE(inv_qty, 0) AS inv_qty,
        COALESCE(inv_val, 0) AS inv_val,
        is_ec_transaction,
        is_ec_display,
        is_ec_avis,
        anomaly_status
    FROM {{ ref('gold_grading_dashboard') }}
)

----------------------------------------------------------------------
-- MAIN QUERY SUMMARY (FULL OUTER JOIN DENGAN MASTER OUTLET)
----------------------------------------------------------------------
SELECT 
    COALESCE(g.year, m.year) AS year,
    COALESCE(g.period, m.period) AS period,
    g.week,
    
    -- TANGGAL 100% MURNI DARI GRADING DASHBOARD
    g.report_date,
    g.visit_date,
    g.inv_date,
    
    -- HIERARKI & MASTER OUTLET
    m.sd_id, m.sd_nm,
    m.nsm_id, m.nsm_nm,
    m.grsm_id, m.grsm_nm,
    m.rsm_id, m.rsm_nm,
    m.ss_id, m.ss_nm,
    COALESCE(g.distributor_id, m.distributor_id) AS distributor_id,
    COALESCE(m.distributor_nm, 'UNKNOWN') AS distributor_nm,
    COALESCE(g.outlet_id, m.outlet_id) AS outlet_id,
    COALESCE(m.cust_nm, 'UNKNOWN OUTLET') AS cust_nm,
    m.city,
    
    -- ATRIBUT IR & SALESMAN MURNI DARI GRADING DASHBOARD
    g.sls_id,
    g.sls_nm,
    g.pcode,
    g.pcode_nm,
    g.subbrand_id, g.subbrand_nm,
    g.cat_id, g.cat_nm,
    g.salesforce_id, g.salesforce_nm,
    g.gsalesforce_id, g.gsalesforce_nm,
    g.group_channel_id, g.group_channel_nm,
    g.div_id, g.div_nm,
    
    -- GRADE & FACING IR
    COALESCE(g.grade, 'UNVISITED / UNGRADED') AS grade,
    g.kode_ap,
    COALESCE(g.facing_qty, 0) AS facing_qty,
    
    -- METRICS KUANTITATIF & FLAGS
    1 AS is_cb_master,
    COALESCE(g.is_ir_detected, 0) AS is_ir_detected,
    COALESCE(g.inv_qty, 0) AS inv_qty,
    COALESCE(g.inv_val, 0) AS inv_val,
    COALESCE(g.is_ec_transaction, 0) AS is_ec_transaction,
    COALESCE(g.is_ec_display, 0) AS is_ec_display,
    COALESCE(g.is_ec_avis, 0) AS is_ec_avis,
    COALESCE(g.anomaly_status, '4. No IR & No Sales') AS anomaly_status

FROM cte_master_outlet_silver m
FULL OUTER JOIN cte_grading_dashboard g
    ON m.distributor_id = g.distributor_id
   AND m.outlet_id      = g.outlet_id
   AND m.year           = g.year
   AND m.period         = g.period