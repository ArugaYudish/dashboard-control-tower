{{
    config(
        materialized = 'table',
        schema = 'spx',
        alias = 'gold_grading_performance_summary',
        pre_hook = "SET LOCAL work_mem = '512MB';",
        indexes = [
            {'columns': ['year', 'period', 'week']},
            {'columns': ['report_date']},
            {'columns': ['sd_id', 'rsm_id', 'ss_id']},
            {'columns': ['distributor_id', 'sls_id', 'outlet_id']},
            {'columns': ['gdiv_id', 'pcode']},
            {'columns': ['subbrand_id']},
            {'columns': ['grade']},
            {'columns': ['is_transaction', 'is_display', 'is_avis']}
        ]
    )
}}

WITH 
----------------------------------------------------------------------
-- 1. BASELINE CUSTOMER BASE & TRANSAKSI SFA (SSoT SILVER)
----------------------------------------------------------------------
cte_silver AS (
    SELECT 
        s.tahun::int AS year,
        s.periode::int AS period,
        COALESCE(s.week::int, 0) AS week,
        
        -- DATES
        s.date AS report_date,
        s.inv_date,
        
        -- HIERARKI PENJUALAN & WILAYAH
        s.source_schema,
        COALESCE(s.gdiv_id, 'UNMAPPED') AS gdiv_id,
        COALESCE(s.gdiv_nm, 'UNMAPPED') AS gdiv_nm,
        COALESCE(s.sd_id, 'UNMAPPED') AS sd_id,
        COALESCE(s.sd_nm, 'UNMAPPED') AS sd_nm,
        COALESCE(s.nsm_id, 'UNMAPPED') AS nsm_id,
        COALESCE(s.nsm_nm, 'UNMAPPED') AS nsm_nm,
        COALESCE(s.grsm_id, 'UNMAPPED') AS grsm_id,
        COALESCE(s.grsm_nm, 'UNMAPPED') AS grsm_nm,
        COALESCE(s.rsm_id, 'UNMAPPED') AS rsm_id,
        COALESCE(s.rsm_nm, 'UNMAPPED') AS rsm_nm,
        COALESCE(s.ss_id, 'UNMAPPED') AS ss_id,
        COALESCE(s.ss_nm, 'UNMAPPED') AS ss_nm,
        s.distributor_id::varchar AS distributor_id,
        COALESCE(s.distributor_nm, 'UNKNOWN') AS distributor_nm,
        s.sls_id::varchar AS sls_id,
        COALESCE(s.sls_nm, 'UNKNOWN / UNMAPPED') AS sls_nm,
        s.cust_id::varchar AS outlet_id,
        s.cust_nm,
        
        -- SALESFORCE & CHANNEL
        COALESCE(s.salesforce_id, 'N/A') AS salesforce_id,
        COALESCE(s.salesforce_nm, 'UNMAPPED_SALESFORCE') AS salesforce_nm,
        COALESCE(s.gsalesforce2_id, 'UNMAPPED_GSALESFORCE') AS gsalesforce_id,
        COALESCE(s.gsalesforce2_nm, 'OTHERS / UNMAPPED') AS gsalesforce_nm,
        COALESCE(s.group_channel_id, 'UNMAPPED_CHANNEL') AS group_channel_id,
        COALESCE(s.group_channel_nm, 'OTHERS / UNMAPPED') AS group_channel_nm,
        
        -- PRODUK & METRICS TRANSAKSI
        COALESCE(NULLIF(s.pcode, ''), 'NO_PCODE') AS pcode,
        COALESCE(NULLIF(s.pcode_nm, ''), 'NO PCODE / UNVISITED') AS pcode_nm,
        COALESCE(NULLIF(s.subbrand_id, ''), 'NO_TRANSACTION') AS subbrand_id,
        COALESCE(NULLIF(s.subbrand_nm, ''), 'NO TRANSACTION / UNVISITED') AS subbrand_nm,
        COALESCE(s.inv_qty, 0) AS inv_qty,
        COALESCE(s.inv_val, 0) AS inv_val,
        
        -- FLAG TRANSAKSI SFA
        s.is_transaction
    FROM {{ ref('silver_oa_performance') }} s
),

----------------------------------------------------------------------
-- 2. DEDUP TARGET CALL HARIAN (KPL) PER SALESMAN
----------------------------------------------------------------------
cte_target_call AS (
    SELECT 
        distributor_id::varchar AS distributor_id,
        sls_id::varchar AS sls_id,
        tgl::date AS report_date,
        SUM(tgt_call::int) AS tgt_call_daily
    FROM raw_ficom_m3.m_nmrc_subdetail
    GROUP BY distributor_id, sls_id, tgl
),

----------------------------------------------------------------------
-- 3. DEDUP AUDIT IR GRADING (AGGREGATE LEVEL TOKO & DIVISI PER PERIODE)
----------------------------------------------------------------------
cte_grading_from_gold AS (
    SELECT 
        COALESCE(NULLIF(TRIM(gdiv_id), ''), '03') AS gdiv_id,
        distributor_id::varchar AS distributor_id,
        outlet_id::varchar AS outlet_id,
        year::int AS year,
        period::int AS period,
        MAX(visit_date::date) AS visit_date,
        MAX(NULLIF(TRIM(grade), '')) AS final_grade,
        SUM(COALESCE(facing_qty, 0)) AS total_facing
    FROM {{ ref('gold_grading_dashboard') }}
    WHERE NULLIF(TRIM(grade), '') IS NOT NULL OR facing_qty > 0
    GROUP BY 
        COALESCE(NULLIF(TRIM(gdiv_id), ''), '03'),
        distributor_id::varchar, 
        outlet_id::varchar, 
        year::int, 
        period::int
)

----------------------------------------------------------------------
-- MAIN QUERY FINAL SUMMARY
----------------------------------------------------------------------
SELECT 
    s.year,
    s.period,
    s.week,
    
    -- DATES
    COALESCE(s.report_date, g.visit_date) AS report_date,
    s.inv_date,
    g.visit_date,
    
    -- HIERARKI PENJUALAN & DIVISI
    s.gdiv_id, s.gdiv_nm,
    s.sd_id, s.sd_nm,
    s.nsm_id, s.nsm_nm,
    s.grsm_id, s.grsm_nm,
    s.rsm_id, s.rsm_nm,
    s.ss_id, s.ss_nm,
    s.sls_id, s.sls_nm,
    s.distributor_id, s.distributor_nm,
    s.outlet_id, s.cust_nm,
    
    -- SALESFORCE & CHANNEL
    s.salesforce_id, s.salesforce_nm,
    s.gsalesforce_id, s.gsalesforce_nm,
    s.group_channel_id, s.group_channel_nm,
    
    -- PRODUK & SUBBRAND
    s.pcode, s.pcode_nm,
    s.subbrand_id, s.subbrand_nm,
    
    -- GRADE DISPLAY IR & FACING PAJANGAN
    COALESCE(g.final_grade, 'UNGRADED / NO GRADE RECORD') AS grade,
    COALESCE(g.total_facing, 0) AS facing_qty,
    
    -- METRICS KUANTITATIF
    1 AS is_cb_active,
    COALESCE(tc.tgt_call_daily, 0) AS tgt_call_daily,
    s.inv_qty,
    s.inv_val,
    
    -- TRI-FLAG KATEGORI KUNJUNGAN UNTUK FILTER METABASE
    s.is_transaction,
    CASE WHEN g.outlet_id IS NOT NULL THEN 1 ELSE 0 END AS is_display,
    CASE WHEN (s.is_transaction = 1 OR g.outlet_id IS NOT NULL) THEN 1 ELSE 0 END AS is_avis

FROM cte_silver s

-- JOIN 1: TARGET CALL HARIAN
LEFT JOIN cte_target_call tc
    ON s.distributor_id = tc.distributor_id
   AND s.sls_id         = tc.sls_id
   AND s.report_date    = tc.report_date

-- JOIN 2: GRADING IR (JANGKAR TOKO FISIK & DIVISI)
LEFT JOIN cte_grading_from_gold g
    ON s.gdiv_id        = g.gdiv_id
   AND s.distributor_id = g.distributor_id
   AND s.outlet_id      = g.outlet_id
   AND s.year           = g.year
   AND s.period         = g.period