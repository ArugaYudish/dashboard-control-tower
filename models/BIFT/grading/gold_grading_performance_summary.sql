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
-- 1. MASTER OUTLET & HIERARKI (SILVER)
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
        kabupaten_name AS city
    FROM {{ ref('silver_oa_performance') }}
),

----------------------------------------------------------------------
-- 2. TARGET CALL (NMRC SUBDETAIL) - LEVEL SALESMAN + TANGGAL/WEEK/PERIODE
----------------------------------------------------------------------
cte_nmrc_tgt_call AS (
    SELECT 
        distributor_id::varchar AS distributor_id,
        sls_id::varchar AS sls_id,
        tgl::date AS report_date,
        tahun::int AS year,
        periode::int AS period,
        week::int AS week,
        SUM(COALESCE(tgt_call::numeric, 0)) AS tgt_call,
        SUM(COALESCE(tcall_glb::numeric, 0)) AS tcall_glb,
        SUM(COALESCE(rcall_kpl::numeric, 0)) AS rcall_kpl,
        SUM(COALESCE(ec_kpl::numeric, 0)) AS ec_kpl
    FROM raw_ficom_m3.m_nmrc_subdetail
    WHERE tgl >= '2025-01-01'
    GROUP BY 
        distributor_id::varchar,
        sls_id::varchar,
        tgl::date,
        tahun::int,
        periode::int,
        week::int
),

----------------------------------------------------------------------
-- 3. ALL ACTIVITY & IR PCODE (GOLD GRADING DASHBOARD - MAIN DATA)
----------------------------------------------------------------------
cte_grading_dashboard AS (
    SELECT 
        year::int AS year,
        period::int AS period,
        week::int AS week,
        visit_date::date AS report_date,
        visit_date,
        inv_date,
        TRIM(distributor_id::varchar) AS distributor_id,
        TRIM(outlet_id::varchar) AS outlet_id,
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
-- MAIN QUERY SUMMARY
----------------------------------------------------------------------
SELECT 
    COALESCE(g.year, s.year, nm.year) AS year,
    COALESCE(g.period, s.period, nm.period) AS period,
    COALESCE(g.week, nm.week) AS week,
    
    -- DATES
    COALESCE(g.report_date, nm.report_date) AS report_date,
    g.visit_date,
    g.inv_date,
    
    -- HIERARKI & OUTLET
    s.sd_id, s.sd_nm,
    s.nsm_id, s.nsm_nm,
    s.grsm_id, s.grsm_nm,
    s.rsm_id, s.rsm_nm,
    s.ss_id, s.ss_nm,
    COALESCE(g.distributor_id, s.distributor_id, nm.distributor_id) AS distributor_id,
    COALESCE(s.distributor_nm, 'UNKNOWN') AS distributor_nm,
    COALESCE(g.outlet_id, s.outlet_id) AS outlet_id,
    COALESCE(s.cust_nm, 'UNKNOWN OUTLET') AS cust_nm,
    s.city,
    
    -- ATRIBUT IR & SALESMAN
    COALESCE(g.sls_id, nm.sls_id) AS sls_id,
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
    
    -- 🎯 METRICS PEMBAGI (%) UNTUK METABASE
    1 AS is_cb_master, -- Dipakai kalau filter PERIODE/BULANAN
    COALESCE(nm.tgt_call, 0) AS tgt_call_nmrc, -- Dipakai kalau filter DAILY / WEEKLY
    COALESCE(nm.tcall_glb, 0) AS tcall_glb_nmrc,
    COALESCE(nm.rcall_kpl, 0) AS rcall_kpl_nmrc,
    COALESCE(nm.ec_kpl, 0) AS ec_kpl_nmrc,
    
    -- PERFORMANCE FLAGS
    COALESCE(g.is_ir_detected, 0) AS is_ir_detected,
    COALESCE(g.inv_qty, 0) AS inv_qty,
    COALESCE(g.inv_val, 0) AS inv_val,
    COALESCE(g.is_ec_transaction, 0) AS is_ec_transaction,
    COALESCE(g.is_ec_display, 0) AS is_ec_display,
    COALESCE(g.is_ec_avis, 0) AS is_ec_avis,
    COALESCE(g.anomaly_status, '4. No IR & No Sales') AS anomaly_status

FROM cte_master_outlet_silver s
FULL OUTER JOIN cte_grading_dashboard g
    ON s.distributor_id = g.distributor_id
   AND s.outlet_id      = g.outlet_id
   AND s.year           = g.year
   AND s.period         = g.period
LEFT JOIN cte_nmrc_tgt_call nm
    ON COALESCE(g.distributor_id, s.distributor_id) = nm.distributor_id
   AND COALESCE(g.sls_id, nm.sls_id)                = nm.sls_id
   AND COALESCE(g.year, s.year)                     = nm.year
   AND COALESCE(g.period, s.period)                 = nm.period
   AND COALESCE(g.report_date, nm.report_date)      = nm.report_date