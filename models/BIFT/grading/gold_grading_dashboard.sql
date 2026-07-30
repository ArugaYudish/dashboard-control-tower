{{
  config(
    materialized = 'table',
    indexes = [
      {'columns': ['distributor_id', 'outlet_id', 'pcode']},
      {'columns': ['anomaly_status']},
      {'columns': ['year', 'period', 'week']}
    ]
  )
}}

WITH latest_fcustsls AS (
    SELECT 
        distributor_id::varchar AS distributor_id,
        cust_id::varchar AS cust_id,
        channel_id::varchar AS channel_id,
        ROW_NUMBER() OVER (
            PARTITION BY distributor_id::varchar, cust_id::varchar 
            ORDER BY tahun DESC, periode DESC
        ) AS rn
    FROM raw_ficom_m3.v_fcustsls_staging
),

-- 1. CTE GRADING STORE LEVEL (Agregasi Max Grade per Cycle Week)
cte_grading_store AS (
    SELECT 
        COALESCE(b.distributor_id::varchar, g.distributor_id::varchar) AS distributor_id,
        COALESCE(b.outlet_id::varchar, g.outlet_id::varchar) AS outlet_id,
        COALESCE(b.sls_id::varchar, g.sls_id::varchar) AS sls_id,
        COALESCE(b.kode_ap::varchar, g.kode_ap::varchar) AS kode_ap,
        c.year,
        c.period,
        c.week,
        MAX(COALESCE(b.visit_date, g.visit_date)) AS max_visit_date,
        MAX(COALESCE(b.team_id::varchar, g.team_id::varchar)) AS team_id,
        MAX(COALESCE(b.grade, g.grade)) AS final_grade
    FROM raw_ficom_m3.t_grading_ir g
    LEFT JOIN raw_ficom_m3.t_grading_banding b
        ON g.distributor_id::varchar = b.distributor_id::varchar
       AND g.sls_id::varchar = b.sls_id::varchar
       AND g.outlet_id::varchar = b.outlet_id::varchar
       AND g.visit_date = b.visit_date
       AND g.kode_ap::varchar = b.kode_ap::varchar
    LEFT JOIN spx.m_cycle3 c ON COALESCE(b.visit_date, g.visit_date)::date = c.cdate::date
    WHERE COALESCE(b.visit_date, g.visit_date) >= '2025-01-01'
    GROUP BY 
        COALESCE(b.distributor_id::varchar, g.distributor_id::varchar),
        COALESCE(b.outlet_id::varchar, g.outlet_id::varchar),
        COALESCE(b.sls_id::varchar, g.sls_id::varchar),
        COALESCE(b.kode_ap::varchar, g.kode_ap::varchar),
        c.year, c.period, c.week
),

-- 2. CTE IR DISPLAY (Di-Agregasi per Cycle Week agar Granularitas SAMA DENGAN SALES)
cte_avis_item AS (
    SELECT 
        COALESCE(m.distributor_id::varchar, a.distributor_id::varchar) AS distributor_id,
        COALESCE(m.outlet_id::varchar, a.outlet_id::varchar) AS outlet_id,
        COALESCE(m.sls_id::varchar, a.sls_id::varchar) AS sls_id,
        COALESCE(m.kode_ap::varchar, a.kode_ap::varchar) AS kode_ap,
        COALESCE(m.pcode::varchar, a.pcode::varchar) AS pcode,
        c.year,
        c.period,
        c.week,
        MAX(COALESCE(m.visit_date, a.visit_date)) AS max_visit_date,
        SUM(COALESCE(m.count_facing::integer, a.count_facing::integer, 0)) AS total_facing,
        1 AS is_in_ir_table
    FROM raw_ficom_m3.t_rcall_avis_d a
    FULL OUTER JOIN raw_ficom_m3.t_rcall_avis_manual m 
        ON a.distributor_id::varchar = m.distributor_id::varchar
       AND a.outlet_id::varchar = m.outlet_id::varchar
       AND a.sls_id::varchar = m.sls_id::varchar
       AND a.kode_ap::varchar = m.kode_ap::varchar
       AND a.pcode::varchar = m.pcode::varchar
       AND a.visit_date = m.visit_date
    LEFT JOIN spx.m_cycle3 c ON COALESCE(m.visit_date, a.visit_date)::date = c.cdate::date
    WHERE COALESCE(m.visit_date, a.visit_date) >= '2025-01-01'
    GROUP BY 
        COALESCE(m.distributor_id::varchar, a.distributor_id::varchar),
        COALESCE(m.outlet_id::varchar, a.outlet_id::varchar),
        COALESCE(m.sls_id::varchar, a.sls_id::varchar),
        COALESCE(m.kode_ap::varchar, a.kode_ap::varchar),
        COALESCE(m.pcode::varchar, a.pcode::varchar),
        c.year, c.period, c.week
),

-- 3. CTE TRANSAKSI SALES SFA (Level Cycle Week)
cte_sales_item AS (
    SELECT 
        s.subdist_id::varchar AS distributor_id,
        s.custno::varchar AS outlet_id,
        s.slsno::varchar AS sls_id,
        s.slsfc_id::varchar AS salesforce_id,
        s.pcode::varchar AS pcode,
        c.year,
        c.period,
        c.week,
        MAX(s.inv_date::date) AS max_inv_date,
        SUM(COALESCE(s.inv_qty::numeric, 0)) AS total_inv_qty,
        SUM(COALESCE(s.inv_val::numeric, 0)) AS total_inv_val
    FROM raw_ho.vfsales_det s
    LEFT JOIN spx.m_cycle3 c ON s.inv_date::date = c.cdate::date
    WHERE s.inv_date >= '2025-01-01'
      AND (COALESCE(s.inv_qty::numeric, 0) > 0 OR COALESCE(s.inv_val::numeric, 0) > 0)
    GROUP BY 
        s.subdist_id::varchar, 
        s.custno::varchar, 
        s.slsno::varchar,
        s.slsfc_id::varchar,
        s.pcode::varchar,
        c.year, c.period, c.week
),

-- 4. KONSOLIDASI ITEM ACTIVITY (1 to 1 JOIN PER CYCLE WEEK & PCODE)
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
        COALESCE(av.max_visit_date, s.max_inv_date) AS activity_date,
        
        COALESCE(av.total_facing, 0) AS total_facing,
        COALESCE(av.is_in_ir_table, 0) AS is_in_ir_table,
        COALESCE(s.total_inv_qty, 0) AS total_inv_qty,
        COALESCE(s.total_inv_val, 0) AS total_inv_val
    FROM cte_avis_item av
    FULL OUTER JOIN cte_sales_item s
        ON av.distributor_id = s.distributor_id
       AND av.outlet_id = s.outlet_id
       AND av.pcode = s.pcode
       AND av.sls_id = s.sls_id
       AND av.year = s.year
       AND av.week = s.week  -- Lock Kunci Tambahan per Week biar Gak Duplikasi
)

-- MAIN QUERY
SELECT 
    act.year,
    act.period,
    act.week,
    
    -- Hierarki Sales
    b.sd_id,
    b.sd_nm,
    b.nsm_id,
    b.nsm_nm,
    b.grsm_id,
    b.grsm_nm,
    b.rsm_id,
    b.rsm_nm,
    b.ss_id,
    b.ss_nm,
    act.sls_id,
    act.distributor_id,

    md.distributor_nm,
    act.outlet_id,
    mc.cust_nm,
    mc.city,
    
    -- Product & Salesforce
    act.pcode,
    act.salesforce_id_sales AS salesforce_id,
    ms.salesforce_nm,
    mgc.gsalesforce_id,
    mgc.gsalesforce_nm,
    mcs.group_channel_id,
    mcs.group_channel_nm,
    mgc.div_id,
    mgc.div_nm,
    
    -- GRADE HANDLING
    CASE 
        WHEN act.is_in_ir_table = 1 THEN COALESCE(gst.final_grade, gst_fallback.final_grade, 'UNGRADED / NO GRADE RECORD')
        ELSE NULL 
    END AS grade,
    
    act.kode_ap,
    CASE 
        WHEN act.is_in_ir_table = 1 THEN COALESCE(gst.team_id, gst_fallback.team_id) 
        ELSE NULL 
    END AS team_id,
    
    act.activity_date AS visit_date,

    -- Metrics IR PCode
    act.total_facing AS facing_qty,
    act.is_in_ir_table AS is_ir_detected,

    -- Metrics Transaksi PCode
    act.total_inv_qty AS inv_qty,
    act.total_inv_val AS inv_val,
    CASE WHEN act.total_inv_qty > 0 THEN 1 ELSE 0 END AS is_transaction_exist,

    -- SENSE CHECK ANOMALY STATUS
    CASE 
        WHEN act.is_in_ir_table = 1 AND act.total_inv_qty > 0 
            THEN '1. IR Terdeteksi & Ada Transaksi'
        WHEN act.is_in_ir_table = 1 AND act.total_inv_qty = 0 
            THEN '2. IR Terdeteksi & TANPA Transaksi (Anomali IR)'
        WHEN act.is_in_ir_table = 0 AND act.total_inv_qty > 0 
            THEN '3. Tidak Ada di Tabel IR & Ada Transaksi (Uncovered Sales)'
        ELSE '4. No IR & No Sales'
    END AS anomaly_status

FROM item_activity act

-- Header Grade Toko (Joined by Year + Week)
LEFT JOIN cte_grading_store gst
    ON act.distributor_id = gst.distributor_id
   AND act.outlet_id = gst.outlet_id
   AND act.sls_id = gst.sls_id
   AND act.kode_ap = gst.kode_ap
   AND act.year = gst.year
   AND act.week = gst.week

LEFT JOIN cte_grading_store gst_fallback
    ON act.distributor_id = gst_fallback.distributor_id
   AND act.outlet_id = gst_fallback.outlet_id
   AND act.sls_id = gst_fallback.sls_id
   AND act.year = gst_fallback.year
   AND act.week = gst_fallback.week

-- Join Master Tables
LEFT JOIN raw_ficom_m3.v_salesman_hierarchy b 
    ON act.sls_id = b.sls_id::varchar  
   AND act.distributor_id = b.distributor_id::varchar

LEFT JOIN raw_ficom_m3.m_distributor md 
    ON act.distributor_id = md.distributor_id::varchar

LEFT JOIN raw_ficom_m3.m_customer mc 
    ON act.distributor_id = mc.distributor_id::varchar 
   AND act.outlet_id = mc.cust_id::varchar 

LEFT JOIN raw_ficom_m3.m_salesforce ms 
    ON act.salesforce_id_sales = ms.salesforce_id::varchar 

LEFT JOIN latest_fcustsls vfs 
    ON act.distributor_id = vfs.distributor_id 
   AND act.outlet_id = vfs.cust_id 
   AND vfs.rn = 1

LEFT JOIN raw_ficom_m3.m_group_channels mcs 
    ON vfs.channel_id = mcs.channel_id::varchar 

LEFT JOIN raw_ficom_m3.m_mapping_group_salesforce mgc 
    ON act.salesforce_id_sales = mgc.salesforce_id::varchar