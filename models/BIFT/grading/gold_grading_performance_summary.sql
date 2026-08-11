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
            {'columns': ['pcode']},
            {'columns': ['subbrand_id']},
            {'columns': ['gdiv_id']},
            {'columns': ['grade']},
            {'columns': ['is_transaction', 'is_display', 'is_avis']}
        ]
    )
}}

WITH 
-- 1. ANCHOR UTAMA: AMBIL SSoT CUSTOMER BASE & TRANSAKSI DARI SILVER
cte_silver AS (
    SELECT 
        s.tahun::int AS year,
        s.periode::int AS period,
        COALESCE(s.week::int, 0) AS week,
        
        -- Tanggal transaksi SFA (atau NULL jika non-purchasing)
        s.date AS report_date,
        s.inv_date,
        
        -- Hierarki Salesman & Wilayah
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
        
        -- Salesforce & Channel
        COALESCE(s.salesforce_id, 'N/A') AS salesforce_id,
        COALESCE(s.salesforce_nm, 'UNMAPPED_SALESFORCE') AS salesforce_nm,
        COALESCE(s.gsalesforce2_id, 'UNMAPPED_GSALESFORCE') AS gsalesforce_id,
        COALESCE(s.gsalesforce2_nm, 'OTHERS / UNMAPPED') AS gsalesforce_nm,
        COALESCE(s.group_channel_id, 'UNMAPPED_CHANNEL') AS group_channel_id,
        COALESCE(s.group_channel_nm, 'OTHERS / UNMAPPED') AS group_channel_nm,
        
        -- Product & Transaksi
        COALESCE(NULLIF(s.pcode, ''), 'NO_PCODE') AS pcode,
        COALESCE(NULLIF(s.pcode_nm, ''), 'NO PCODE / UNVISITED') AS pcode_nm,
        COALESCE(NULLIF(s.subbrand_id, ''), 'NO_TRANSACTION') AS subbrand_id,
        COALESCE(NULLIF(s.subbrand_nm, ''), 'NO TRANSACTION / UNVISITED') AS subbrand_nm,
        COALESCE(s.inv_qty, 0) AS inv_qty,
        COALESCE(s.inv_val, 0) AS inv_val,
        s.is_transaction
    FROM {{ ref('silver_oa_performance') }} s
),

-- 2. DEDUP IR GRADING (AGGREGATE LEVEL TOKO PER MINGGU/PERIODE)
cte_grading_store AS (
    SELECT 
        g.distributor_id::varchar AS distributor_id,
        g.outlet_id::varchar AS outlet_id,
        c.year::int AS year,
        c.period::int AS period,
        c.week::int AS week,
        MAX(g.visit_date::date) AS ir_visit_date,
        MAX(COALESCE(b.grade, g.grade)) AS final_grade
    FROM raw_ficom_m3.t_grading_ir g
    LEFT JOIN raw_ficom_m3.t_grading_banding b
        ON g.distributor_id::varchar = b.distributor_id::varchar
       AND g.outlet_id::varchar      = b.outlet_id::varchar
       AND g.sls_id::varchar         = b.sls_id::varchar
       AND g.kode_ap::varchar        = b.kode_ap::varchar
       AND g.visit_date              = b.visit_date
    LEFT JOIN spx.m_cycle3 c ON g.visit_date::date = c.cdate::date
    WHERE g.visit_date >= '2025-01-01'
      AND NULLIF(TRIM(COALESCE(b.grade, g.grade)), '') IS NOT NULL
    GROUP BY g.distributor_id::varchar, g.outlet_id::varchar, c.year, c.period, c.week
),

-- 3. DEDUP FACING DISPLAY PER TOKO PER PCODE PER MINGGU
cte_facing_item AS (
    SELECT 
        r.distributor_id::varchar AS distributor_id,
        r.outlet_id::varchar AS outlet_id,
        r.pcode::varchar AS pcode,
        c.year::int AS year,
        c.period::int AS period,
        c.week::int AS week,
        SUM(COALESCE(r.count_facing::integer, 0)) AS total_facing
    FROM raw_ficom_m3.t_rcall_avis_d r
    LEFT JOIN spx.m_cycle3 c ON r.visit_date::date = c.cdate::date
    WHERE r.visit_date >= '2025-01-01'
    GROUP BY r.distributor_id::varchar, r.outlet_id::varchar, r.pcode::varchar, c.year, c.period, c.week
)

-- MAIN MODEL FINAL GABUNGAN
SELECT 
    s.year,
    s.period,
    s.week,
    
    -- Tanggal Report (Gunakan Tanggal IR Jika Transaksi Kosong)
    COALESCE(s.report_date, gst.ir_visit_date) AS report_date,
    s.inv_date,
    gst.ir_visit_date AS visit_date,
    
    -- Hierarki Sales
    s.gdiv_id, s.gdiv_nm,
    s.sd_id, s.sd_nm,
    s.nsm_id, s.nsm_nm,
    s.grsm_id, s.grsm_nm,
    s.rsm_id, s.rsm_nm,
    s.ss_id, s.ss_nm,
    s.sls_id, s.sls_nm,
    s.distributor_id, s.distributor_nm,
    s.outlet_id, s.cust_nm,
    
    -- Salesforce & Channel
    s.salesforce_id, s.salesforce_nm,
    s.gsalesforce_id, s.gsalesforce_nm,
    s.group_channel_id, s.group_channel_nm,
    
    -- Product
    s.pcode, s.pcode_nm,
    s.subbrand_id, s.subbrand_nm,
    
    -- Grade & Facing Display
    COALESCE(gst.final_grade, 'UNGRADED / NO GRADE RECORD') AS grade,
    COALESCE(f.total_facing, 0) AS facing_qty,
    
    -- Metrics
    1 AS is_cb_active,
    s.inv_qty,
    s.inv_val,
    
    -- Flag EC (Effective Call)
    s.is_transaction,
    CASE WHEN gst.outlet_id IS NOT NULL THEN 1 ELSE 0 END AS is_display,
    CASE WHEN (s.is_transaction = 1 OR gst.outlet_id IS NOT NULL) THEN 1 ELSE 0 END AS is_avis

FROM cte_silver s

-- JOIN 1: PENEMPELAN GRADE TOKO (TANPA KUNCI GDIV_ID KARENA IR HANYA DI DIVISI 03)
LEFT JOIN cte_grading_store gst
    ON s.distributor_id = gst.distributor_id
   AND s.outlet_id     = gst.outlet_id
   AND s.year          = gst.year
   AND s.period        = gst.period
   AND (s.week = gst.week OR s.week = 0)

-- JOIN 2: PENEMPELAN FACING PER PCODE
LEFT JOIN cte_facing_item f
    ON s.distributor_id = f.distributor_id
   AND s.outlet_id     = f.outlet_id
   AND s.pcode         = f.pcode
   AND s.year          = f.year
   AND s.period        = f.period
   AND (s.week = f.week OR s.week = 0);