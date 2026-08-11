{{
    config(
        materialized = 'table',
        indexes = [
            {'columns': ['year', 'period', 'week']},
            {'columns': ['report_date']},
            {'columns': ['sd_id', 'rsm_id', 'ss_id']},
            {'columns': ['distributor_id', 'sls_id', 'outlet_id']},
            {'columns': ['pcode']},
            {'columns': ['subbrand_id']},
            {'columns': ['gsalesforce_id']},
            {'columns': ['group_channel_id']}
        ]
    )
}}

WITH 
-- 1. BASELINE DARI SILVER OA PERFORMANCE
cte_silver AS (
    SELECT 
        s.tahun::int AS year,
        s.periode::int AS period,
        s.week::int AS week,
        s.date AS report_date,
        
        -- HIERARKI M3
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
        
        -- SALESFORCE & CHANNEL
        COALESCE(s.salesforce_id, 'N/A') AS salesforce_id,
        COALESCE(s.gsalesforce2_id, 'UNMAPPED_GSALESFORCE') AS gsalesforce_id,
        COALESCE(s.gsalesforce2_nm, 'OTHERS / UNMAPPED') AS gsalesforce_nm,
        COALESCE(s.group_channel_id, 'UNMAPPED_CHANNEL') AS group_channel_id,
        COALESCE(s.group_channel_nm, 'OTHERS / UNMAPPED') AS group_channel_nm,
        
        -- PRODUK
        COALESCE(s.subbrand_id, 'NO_TRANSACTION') AS subbrand_id,
        COALESCE(s.subbrand_nm, 'NO TRANSACTION / UNVISITED') AS subbrand_nm,
        COALESCE(s.pcode, 'NO_PCODE') AS pcode,
        COALESCE(s.pcode_nm, 'NO PCODE / UNVISITED') AS pcode_nm,
        
        -- METRICS TRANSAKSI MURNI
        COALESCE(s.inv_qty, 0) AS inv_qty,
        COALESCE(s.inv_val, 0) AS inv_val,
        
        -- FLAG CB & OA
        1 AS is_cb_active,
        CASE WHEN s.is_transaction = 1 THEN 1 ELSE 0 END AS is_visited
    FROM bift.silver_oa_performance s
),

-- 2. TARGET CALL HARIAN (KPL)
cte_target_call AS (
    SELECT 
        distributor_id::varchar AS distributor_id,
        sls_id::varchar AS sls_id,
        tgl::date AS report_date,
        SUM(tgt_call::int) AS tgt_call_daily
    FROM raw_ficom_m3.m_nmrc_subdetail
    GROUP BY distributor_id, sls_id, tgl
),

-- 3. GRADE & FACING IR DARI DASHBOARD DETAIL (AGGREGATE TANPA KUNCI REPORT_DATE KETAT)
cte_grading AS (
    SELECT 
        year, 
        period, 
        distributor_id, 
        outlet_id, 
        pcode,
        MAX(grade) AS grade,
        SUM(facing_qty) AS facing_qty
    FROM {{ ref('gold_grading_dashboard') }}
    WHERE grade IS NOT NULL
    GROUP BY year, period, distributor_id, outlet_id, pcode
)

-- MAIN MODEL FINAL
SELECT 
    s.year,
    s.period,
    s.week,
    s.report_date,
    
    -- HIERARKI PENJUALAN M3
    s.sd_id, s.sd_nm,
    s.nsm_id, s.nsm_nm,
    s.grsm_id, s.grsm_nm,
    s.rsm_id, s.rsm_nm,
    s.ss_id, s.ss_nm,
    s.sls_id, s.sls_nm,
    s.distributor_id, s.distributor_nm,
    s.outlet_id,
    
    -- SALESFORCE & CHANNEL
    s.salesforce_id,
    s.gsalesforce_id,
    s.gsalesforce_nm,
    s.group_channel_id,
    s.group_channel_nm,
    
    -- PRODUK & GRADE (DENGAN FALLBACK JELAS)
    s.subbrand_id,
    s.subbrand_nm,
    s.pcode,
    s.pcode_nm,
    COALESCE(g.grade, 'UNGRADED / NO GRADE RECORD') AS grade,
    
    -- METRICS
    s.is_cb_active,
    COALESCE(tc.tgt_call_daily, 0) AS tgt_call_daily,
    s.inv_qty,
    s.inv_val,
    COALESCE(g.facing_qty, 0) AS facing_qty,
    s.is_visited

FROM cte_silver s

-- JOIN TARGET CALL
LEFT JOIN cte_target_call tc
    ON s.distributor_id = tc.distributor_id
   AND s.sls_id = tc.sls_id
   AND s.report_date = tc.report_date

-- JOIN GRADE DISPLAY IR (JOIN KE BULAN, DISTRIBUTOR, OUTLET & PCODE)
LEFT JOIN cte_grading g
    ON s.distributor_id = g.distributor_id
   AND s.outlet_id = g.outlet_id
   AND s.year = g.year
   AND s.period = g.period
   AND s.pcode = g.pcode