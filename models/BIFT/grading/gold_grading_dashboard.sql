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
        distributor_id,
        cust_id,
        channel_id,
        ROW_NUMBER() OVER (
            PARTITION BY distributor_id, cust_id 
            ORDER BY tahun DESC, periode DESC
        ) AS rn
    FROM raw_ficom_m3.v_fcustsls_staging
),

-- 1. CTE IR / VISIBILITY (AI + MANUAL BANDING) LOCKED TO PCODE & VISIT
cte_avis AS (
    SELECT 
        COALESCE(m.distributor_id::varchar, a.distributor_id::varchar) AS distributor_id,
        COALESCE(m.outlet_id::varchar, a.outlet_id::varchar) AS outlet_id,
        COALESCE(m.sls_id::varchar, a.sls_id::varchar) AS sls_id,
        COALESCE(m.kode_ap::varchar, a.kode_ap::varchar) AS kode_ap,
        COALESCE(m.pcode::varchar, a.pcode::varchar) AS pcode,
        COALESCE(m.visit_date, a.visit_date) AS visit_date,
        SUM(COALESCE(m.count_facing::integer, a.count_facing::integer, 0)) AS total_facing
    FROM raw_ficom_m3.t_rcall_avis_d a
    FULL OUTER JOIN raw_ficom_m3.t_rcall_avis_manual m 
        ON a.distributor_id::varchar = m.distributor_id::varchar
       AND a.outlet_id::varchar = m.outlet_id::varchar
       AND a.sls_id::varchar = m.sls_id::varchar
       AND a.kode_ap::varchar = m.kode_ap::varchar
       AND a.pcode::varchar = m.pcode::varchar
       AND a.visit_date = m.visit_date
    GROUP BY 
        COALESCE(m.distributor_id::varchar, a.distributor_id::varchar),
        COALESCE(m.outlet_id::varchar, a.outlet_id::varchar),
        COALESCE(m.sls_id::varchar, a.sls_id::varchar),
        COALESCE(m.kode_ap::varchar, a.kode_ap::varchar),
        COALESCE(m.pcode::varchar, a.pcode::varchar),
        COALESCE(m.visit_date, a.visit_date)
),

-- 2. CTE GRADING SUMMARY (STORE VISIT LEVEL)
cte_grading AS (
    SELECT 
        COALESCE(b.distributor_id::varchar, g.distributor_id::varchar) AS distributor_id,
        COALESCE(b.outlet_id::varchar, g.outlet_id::varchar) AS outlet_id,
        COALESCE(b.sls_id::varchar, g.sls_id::varchar) AS sls_id,
        COALESCE(b.kode_ap::varchar, g.kode_ap::varchar) AS kode_ap,
        COALESCE(b.visit_date, g.visit_date) AS visit_date,
        COALESCE(b.salesforce_id::varchar, g.salesforce_id::varchar) AS salesforce_id,
        COALESCE(b.team_id::varchar, g.team_id::varchar) AS team_id,
        COALESCE(b.grade, g.grade) AS final_grade
    FROM raw_ficom_m3.t_grading_ir g
    LEFT JOIN raw_ficom_m3.t_grading_banding b
        ON g.distributor_id::varchar = b.distributor_id::varchar
       AND g.sls_id::varchar = b.sls_id::varchar
       AND g.outlet_id::varchar = b.outlet_id::varchar
       AND g.visit_date = b.visit_date
       AND g.kode_ap::varchar = b.kode_ap::varchar
),

-- 3. CTE TRANSAKSI SALES (LOCKED TO PCODE & CYCLE WEEK)
cte_sales AS (
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
    WHERE (COALESCE(s.inv_qty::numeric, 0) > 0 OR COALESCE(s.inv_val::numeric, 0) > 0)
    GROUP BY 
        s.subdist_id::varchar, 
        s.custno::varchar, 
        s.slsno::varchar,
        s.slsfc_id::varchar,
        s.pcode::varchar,
        c.year, c.period, c.week
),

-- 4. COMBINE IR + GRADING (LOCKED BY VISIT KEY)
cte_ir_graded AS (
    SELECT 
        av.distributor_id,
        av.outlet_id,
        av.sls_id,
        av.kode_ap,
        av.pcode,
        av.visit_date,
        av.total_facing,
        gr.salesforce_id,
        gr.team_id,
        gr.final_grade,
        c.year,
        c.period,
        c.week
    FROM cte_avis av
    LEFT JOIN cte_grading gr
        ON av.distributor_id = gr.distributor_id
       AND av.outlet_id = gr.outlet_id
       AND av.sls_id = gr.sls_id
       AND av.kode_ap = gr.kode_ap
       AND av.visit_date = gr.visit_date
    LEFT JOIN spx.m_cycle3 c 
        ON av.visit_date::date = c.cdate::date
),

-- 5. BASE FULL OUTER JOIN BETWEEN IR_GRADED AND SALES (LOCKED TO DIST + OUTLET + PCODE + WEEK)
base_activity AS (
    SELECT 
        COALESCE(ir.distributor_id, s.distributor_id) AS distributor_id,
        COALESCE(ir.outlet_id, s.outlet_id) AS outlet_id,
        COALESCE(ir.sls_id, s.sls_id) AS sls_id,
        COALESCE(ir.salesforce_id, s.salesforce_id) AS salesforce_id,
        COALESCE(ir.pcode, s.pcode) AS pcode,
        COALESCE(ir.kode_ap, 'N/A') AS kode_ap,
        COALESCE(ir.year, s.year) AS year,
        COALESCE(ir.period, s.period) AS period,
        COALESCE(ir.week, s.week) AS week,
        COALESCE(ir.visit_date, s.max_inv_date) AS activity_date,
        
        ir.final_grade,
        ir.team_id,
        COALESCE(ir.total_facing, 0) AS total_facing,
        COALESCE(s.total_inv_qty, 0) AS total_inv_qty,
        COALESCE(s.total_inv_val, 0) AS total_inv_val
    FROM cte_ir_graded ir
    FULL OUTER JOIN cte_sales s
        ON ir.distributor_id::integer = s.distributor_id::integer
       AND ir.outlet_id::integer = s.outlet_id::integer
       AND ir.pcode::varchar = s.pcode::varchar
       AND ir.year = s.year
       AND ir.week = s.week
)

-- MAIN QUERY
SELECT 
    base.year,
    base.period,
    base.week,
    
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
    base.sls_id,
    base.distributor_id,

    md.distributor_nm,
    base.outlet_id,
    mc.cust_nm,
    mc.city,
    
    -- Product & Salesforce
    base.pcode,
    base.salesforce_id,
    ms.salesforce_nm,
    mgc.gsalesforce_id,
    mgc.gsalesforce_nm,
    mcs.group_channel_id,
    mcs.group_channel_nm,
    mgc.div_id,
    mgc.div_nm,
    
    base.final_grade AS grade,
    base.kode_ap,
    base.team_id,
    base.activity_date AS visit_date,

    -- Metrics IR
    base.total_facing AS facing_qty,
    CASE WHEN base.total_facing > 0 THEN 1 ELSE 0 END AS is_ir_detected,

    -- Metrics Transaksi
    base.total_inv_qty AS inv_qty,
    base.total_inv_val AS inv_val,
    CASE WHEN base.total_inv_qty > 0 THEN 1 ELSE 0 END AS is_transaction_exist,

    -- SENSE CHECK ANOMALY STATUS PRECISE LEVEL
    CASE 
        WHEN base.total_facing > 0 AND base.total_inv_qty > 0 
            THEN '1. IR Terdeteksi & Ada Transaksi'
        WHEN base.total_facing > 0 AND base.total_inv_qty = 0 
            THEN '2. IR Terdeteksi & TANPA Transaksi (Anomali)'
        WHEN base.total_facing = 0 AND base.total_inv_qty > 0 
            THEN '3. IR Tidak Terdeteksi & Ada Transaksi'
        ELSE '4. No Visit/IR & No Sales'
    END AS anomaly_status

FROM base_activity base

LEFT JOIN raw_ficom_m3.v_salesman_hierarchy b 
    ON base.sls_id::varchar = b.sls_id::varchar  
   AND base.distributor_id::varchar = b.distributor_id::varchar

LEFT JOIN raw_ficom_m3.m_distributor md 
    ON base.distributor_id::varchar = md.distributor_id::varchar

LEFT JOIN raw_ficom_m3.m_customer mc 
    ON base.distributor_id::varchar = mc.distributor_id::varchar 
   AND base.outlet_id::varchar = mc.cust_id::varchar 

LEFT JOIN raw_ficom_m3.m_salesforce ms 
    ON base.salesforce_id::varchar = ms.salesforce_id::varchar 

LEFT JOIN latest_fcustsls vfs 
    ON base.distributor_id::varchar = vfs.distributor_id::varchar 
   AND base.outlet_id::varchar = vfs.cust_id::varchar 
   AND vfs.rn = 1

LEFT JOIN raw_ficom_m3.m_group_channels mcs 
    ON vfs.channel_id::varchar = mcs.channel_id::varchar 

LEFT JOIN raw_ficom_m3.m_mapping_group_salesforce mgc 
    ON base.salesforce_id::varchar = mgc.salesforce_id::varchar