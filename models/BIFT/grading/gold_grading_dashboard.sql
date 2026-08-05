{{
  config(
    materialized = 'table',
    indexes = [
      {'columns': ['year', 'period', 'week']},
      {'columns': ['report_date', 'visit_date', 'inv_date']},
      {'columns': ['sd_id', 'nsm_id', 'grsm_id', 'rsm_id', 'ss_id']},
      {'columns': ['distributor_id', 'outlet_id', 'pcode']},
      {'columns': ['subbrand_id']},
      {'columns': ['gsalesforce_id']},
      {'columns': ['group_channel_id']},
      {'columns': ['sls_id']}
    ]
  )
}}

-- 0. CTE STAGING OUTLET & SALESFORCE FALLBACK
WITH latest_fcustsls AS (
    SELECT 
        distributor_id::varchar AS distributor_id,
        cust_id::varchar AS cust_id,
        channel_id::varchar AS channel_id,
        salesforce_id::varchar AS salesforce_id,
        ROW_NUMBER() OVER (
            PARTITION BY distributor_id::varchar, cust_id::varchar 
            ORDER BY tahun DESC, periode DESC
        ) AS rn
    FROM raw_ficom_m3.v_fcustsls_staging
),

-- 1. ANCHOR HIERARKI SALESMAN M3
cte_m3_hierarchy AS (
    SELECT DISTINCT
        h.distributor_id::varchar AS distributor_id,
        h.sls_id::varchar AS sls_id,
        COALESCE(ms.sls_nm, 'UNKNOWN / UNMAPPED') AS sls_nm,
        h.sd_id, h.sd_nm,
        h.nsm_id, h.nsm_nm,
        h.grsm_id, h.grsm_nm,
        h.rsm_id, h.rsm_nm,
        h.ss_id, h.ss_nm
    FROM raw_ficom_m3.v_salesman_hierarchy h
    LEFT JOIN raw_ficom_m3.m_salesman ms
        ON h.sls_id::varchar = ms.sls_id::varchar
       AND h.distributor_id::varchar = ms.distributor_id::varchar
),

-- 2A. GRADING STORE LEVEL
cte_grading_store AS (
    SELECT 
        g.distributor_id::varchar AS distributor_id,
        g.outlet_id::varchar AS outlet_id,
        g.sls_id::varchar AS sls_id,
        g.kode_ap::varchar AS kode_ap,
        c.year,
        c.period,
        c.week,
        MAX(COALESCE(b.visit_date, g.visit_date)) AS max_visit_date,
        MAX(COALESCE(b.team_id::varchar, g.team_id::varchar)) AS team_id,
        MAX(COALESCE(b.grade, g.grade)) AS final_grade
    FROM raw_ficom_m3.t_grading_ir g
    INNER JOIN cte_m3_hierarchy h 
        ON g.sls_id::varchar = h.sls_id 
       AND g.distributor_id::varchar = h.distributor_id
    LEFT JOIN raw_ficom_m3.t_grading_banding b
        ON g.distributor_id::varchar = b.distributor_id::varchar
       AND g.outlet_id::varchar      = b.outlet_id::varchar
       AND g.sls_id::varchar         = b.sls_id::varchar
       AND g.kode_ap::varchar        = b.kode_ap::varchar
       AND g.visit_date              = b.visit_date
       AND COALESCE(g.team_id::varchar, '') = COALESCE(b.team_id::varchar, '')
    LEFT JOIN spx.m_cycle3 c ON g.visit_date::date = c.cdate::date
    WHERE g.visit_date >= '2025-01-01'
    GROUP BY 
        g.distributor_id::varchar, g.outlet_id::varchar, g.sls_id::varchar, g.kode_ap::varchar,
        c.year, c.period, c.week
),

-- 2B. GRADING STORE FALLBACK (Store + Week Unik)
cte_grading_store_fallback AS (
    SELECT 
        distributor_id, outlet_id, year, period, week,
        MAX(team_id) AS team_id,
        MAX(final_grade) AS final_grade
    FROM cte_grading_store
    GROUP BY distributor_id, outlet_id, year, period, week
),

-- 3. IR DISPLAY
cte_manual_dedup AS (
    SELECT 
        distributor_id::varchar AS distributor_id, outlet_id::varchar AS outlet_id,
        sls_id::varchar AS sls_id, kode_ap::varchar AS kode_ap, pcode::varchar AS pcode, visit_date,
        MAX(count_facing::integer) AS count_facing
    FROM raw_ficom_m3.t_rcall_avis_manual
    WHERE visit_date >= '2025-01-01'
    GROUP BY 1, 2, 3, 4, 5, 6
),

cte_avis_raw_joined AS (
    SELECT 
        a.distributor_id::varchar AS distributor_id, a.outlet_id::varchar AS outlet_id,
        a.sls_id::varchar AS sls_id, a.kode_ap::varchar AS kode_ap, a.pcode::varchar AS pcode, a.visit_date AS visit_date,
        COALESCE(m.count_facing, a.count_facing::integer, 0) AS count_facing
    FROM raw_ficom_m3.t_rcall_avis_d a
    INNER JOIN cte_m3_hierarchy h 
        ON a.sls_id::varchar = h.sls_id AND a.distributor_id::varchar = h.distributor_id
    LEFT JOIN cte_manual_dedup m 
        ON a.distributor_id::varchar = m.distributor_id AND a.outlet_id::varchar = m.outlet_id
       AND a.sls_id::varchar = m.sls_id AND a.kode_ap::varchar = m.kode_ap
       AND a.pcode::varchar = m.pcode AND a.visit_date = m.visit_date
    WHERE a.visit_date >= '2025-01-01'
),

cte_avis_item AS (
    SELECT 
        r.distributor_id, r.outlet_id, r.pcode, c.year, c.period, c.week,
        MAX(r.sls_id) AS sls_id, MAX(r.kode_ap) AS kode_ap, MAX(r.visit_date) AS max_visit_date,
        SUM(r.count_facing) AS total_facing, 1 AS is_in_ir_table
    FROM cte_avis_raw_joined r
    LEFT JOIN spx.m_cycle3 c ON r.visit_date::date = c.cdate::date
    GROUP BY r.distributor_id, r.outlet_id, r.pcode, c.year, c.period, c.week
),

-- 4. TRANSAKSI SALES SFA
cte_sales_item AS (
    SELECT 
        s.subdist_id::varchar AS distributor_id, s.custno::varchar AS outlet_id, s.pcode::varchar AS pcode,
        c.year, c.period, c.week,
        MAX(s.slsno::varchar) AS sls_id, MAX(s.slsfc_id::varchar) AS salesforce_id, MAX(s.inv_date::date) AS max_inv_date,
        SUM(COALESCE(s.inv_qty::numeric, 0)) AS total_inv_qty,
        SUM(COALESCE(s.inv_val::numeric, 0)) AS total_inv_val
    FROM raw_ho.vfsales_det s
    INNER JOIN cte_m3_hierarchy h 
        ON s.slsno::varchar = h.sls_id AND s.subdist_id::varchar = h.distributor_id
    LEFT JOIN spx.m_cycle3 c ON s.inv_date::date = c.cdate::date
    WHERE s.inv_date >= '2025-01-01'
      AND (COALESCE(s.inv_qty::numeric, 0) > 0 OR COALESCE(s.inv_val::numeric, 0) > 0)
    GROUP BY s.subdist_id::varchar, s.custno::varchar, s.pcode::varchar, c.year, c.period, c.week
),

-- 5. KONSOLIDASI ITEM ACTIVITY (FIX DUPES & EXPLICIT DATES)
item_activity AS (
    SELECT 
        COALESCE(av.distributor_id, s.distributor_id) AS distributor_id,
        COALESCE(av.outlet_id, s.outlet_id) AS outlet_id,
        COALESCE(av.sls_id, s.sls_id) AS sls_id,
        s.salesforce_id AS salesforce_id_sales,
        COALESCE(av.pcode, s.pcode) AS pcode,
        COALESCE(av.kode_ap, 'N/A') AS kode_ap,
        COALESCE(av.year, s.year) AS year,
        COALESCE(av.period, s.period) AS period,
        COALESCE(av.week, s.week) AS week,
        
        -- Tanggal Spesifik & Primary Fallback
        av.max_visit_date AS visit_date,
        s.max_inv_date AS inv_date,
        COALESCE(av.max_visit_date, s.max_inv_date) AS activity_date,
        
        COALESCE(av.total_facing, 0) AS total_facing,
        COALESCE(av.is_in_ir_table, 0) AS is_in_ir_table,
        COALESCE(s.total_inv_qty, 0) AS total_inv_qty,
        COALESCE(s.total_inv_val, 0) AS total_inv_val
    FROM cte_avis_item av
    FULL OUTER JOIN cte_sales_item s
        ON av.distributor_id = s.distributor_id 
       AND av.outlet_id = s.outlet_id
       AND av.sls_id = s.sls_id  -- 👈 FIX: Cegah duplikasi antar-salesman berbeda
       AND av.pcode = s.pcode 
       AND av.year = s.year 
       AND av.week = s.week
)

-- MAIN QUERY FULL ATTRIBUTES & FALLBACKS
SELECT 
    act.year,
    act.period,
    act.week,
    
    -- TANGGAL EKSPLISIT DAN PEMERSATU (SAFE FOR BI)
    act.activity_date AS report_date, -- 👈 Core Fallback Date
    act.visit_date,                   -- 👈 Tanggal IR Murni (NULL jika transaksi tanpa visit)
    act.inv_date,                     -- 👈 Tanggal Invoice Murni
    
    -- 1. HIERARKI SALESMAN & NAMA SALESMAN
    h.sd_id, h.sd_nm,
    h.nsm_id, h.nsm_nm,
    h.grsm_id, h.grsm_nm,
    h.rsm_id, h.rsm_nm,
    h.ss_id, h.ss_nm,
    act.sls_id,
    COALESCE(h.sls_nm, 'UNKNOWN / UNMAPPED') AS sls_nm,
    
    -- 2. DISTRIBUTOR & OUTLET
    act.distributor_id,
    md.distributor_nm,
    act.outlet_id,
    mc.cust_nm,
    mc.city,
    
    -- 3. PRODUCT & SUBBRAND HIERARCHY
    act.pcode,
    COALESCE(mp.pcode_nm, 'PCODE - ' || act.pcode) AS pcode_nm,
    COALESCE(mms.subbrand_id, 'UNMAPPED_SUBBRAND') AS subbrand_id,
    COALESCE(mms.subbrand_nm, 'OTHERS / UNMAPPED') AS subbrand_nm,
    COALESCE(mms.cat_id, 'UNMAPPED_CAT') AS cat_id,
    COALESCE(mms.cat_nm, 'OTHERS / UNMAPPED') AS cat_nm,
    COALESCE(mms.gdiv_id, 'UNMAPPED_GDIV') AS gdiv_id,
    COALESCE(mms.gdiv_nm, 'OTHERS / UNMAPPED') AS gdiv_nm,
    
    -- 4. SALESFORCE & GROUP CHANNEL
    COALESCE(act.salesforce_id_sales, vfs.salesforce_id, 'N/A') AS salesforce_id,
    COALESCE(ms.salesforce_nm, 'UNMAPPED SALESFORCE') AS salesforce_nm,
    COALESCE(mgc.gsalesforce_id, 'UNMAPPED_GSALESFORCE') AS gsalesforce_id,
    COALESCE(mgc.gsalesforce_nm, 'OTHERS / UNMAPPED') AS gsalesforce_nm,
    COALESCE(mcs.group_channel_id, 'UNMAPPED_CHANNEL') AS group_channel_id,
    COALESCE(mcs.group_channel_nm, 'OTHERS / UNMAPPED') AS group_channel_nm,
    COALESCE(mgc.div_id, 'UNMAPPED_DIV') AS div_id,
    COALESCE(mgc.div_nm, 'OTHERS / UNMAPPED') AS div_nm,
    
    -- 5. GRADE TOKO
    CASE 
        WHEN act.is_in_ir_table = 1 THEN COALESCE(gst.final_grade, gst_fb.final_grade, 'UNGRADED / NO GRADE RECORD')
        ELSE NULL 
    END AS grade,
    act.kode_ap,
    
    -- 6. METRICS
    act.total_facing AS facing_qty,
    act.is_in_ir_table AS is_ir_detected,
    act.total_inv_qty AS inv_qty,
    act.total_inv_val AS inv_val,
    
    -- 7. EFFECTIVE CALL (EC) INDICATORS
    CASE WHEN act.total_inv_qty > 0 THEN 1 ELSE 0 END AS is_ec_transaction,
    CASE WHEN act.is_in_ir_table = 1 THEN 1 ELSE 0 END AS is_ec_display,
    CASE WHEN (act.total_inv_qty > 0 OR act.is_in_ir_table = 1) THEN 1 ELSE 0 END AS is_ec_avis,

    -- 8. ANOMALY STATUS
    CASE 
        WHEN act.is_in_ir_table = 1 AND act.total_inv_qty > 0 THEN '1. IR Terdeteksi & Ada Transaksi'
        WHEN act.is_in_ir_table = 1 AND act.total_inv_qty = 0 THEN '2. IR Terdeteksi & TANPA Transaksi (Anomali IR)'
        WHEN act.is_in_ir_table = 0 AND act.total_inv_qty > 0 THEN '3. Tidak Ada di Tabel IR & Ada Transaksi (Uncovered Sales)'
        ELSE '4. No IR & No Sales'
    END AS anomaly_status

FROM item_activity act

-- LEFT JOIN HIERARKI M3
LEFT JOIN cte_m3_hierarchy h ON act.sls_id = h.sls_id AND act.distributor_id = h.distributor_id

-- HEADER GRADE TOKO
LEFT JOIN cte_grading_store gst
    ON act.distributor_id = gst.distributor_id AND act.outlet_id = gst.outlet_id
   AND act.sls_id = gst.sls_id AND act.kode_ap = gst.kode_ap
   AND act.year = gst.year AND act.week = gst.week

LEFT JOIN cte_grading_store_fallback gst_fb
    ON act.distributor_id = gst_fb.distributor_id AND act.outlet_id = gst_fb.outlet_id
   AND act.year = gst_fb.year AND act.week = gst_fb.week

-- MASTER PRODUCT & SUBBRAND MAPPING
LEFT JOIN raw_ficom_m3.m_product mp 
    ON act.pcode = mp.pcode::varchar

LEFT JOIN raw_ficom_m3.m_mapping_subbrand mms 
    ON (mp.prlin::varchar || mp.brand::varchar || mp.sbra1::varchar) = mms.subbrand_id::varchar

-- MASTER DISTRIBUTOR & CUSTOMER
LEFT JOIN raw_ficom_m3.m_distributor md ON act.distributor_id = md.distributor_id::varchar
LEFT JOIN raw_ficom_m3.m_customer mc ON act.distributor_id = mc.distributor_id::varchar AND act.outlet_id = mc.cust_id::varchar

-- STAGING OUTLET
LEFT JOIN latest_fcustsls vfs 
    ON act.distributor_id = vfs.distributor_id 
   AND act.outlet_id = vfs.cust_id 
   AND vfs.rn = 1

-- MASTER SALESFORCE
LEFT JOIN raw_ficom_m3.m_salesforce ms 
    ON COALESCE(act.salesforce_id_sales, vfs.salesforce_id) = ms.salesforce_id::varchar

LEFT JOIN raw_ficom_m3.m_mapping_group_salesforce mgc 
    ON COALESCE(act.salesforce_id_sales, vfs.salesforce_id) = mgc.salesforce_id::varchar

LEFT JOIN raw_ficom_m3.m_group_channels mcs 
    ON vfs.channel_id = mcs.channel_id::varchar