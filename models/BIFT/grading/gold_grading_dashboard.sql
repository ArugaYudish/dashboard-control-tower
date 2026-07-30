{{
  config(
    materialized = 'table',
    indexes = [
      {'columns': ['distributor_id', 'outlet_id']},
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

-- 1. CTE FACING IR (Agregasi per Week + Store)
cte_facing AS (
    SELECT 
        COALESCE(m.distributor_id::varchar, a.distributor_id::varchar) AS distributor_id,
        COALESCE(m.outlet_id::varchar, a.outlet_id::varchar) AS outlet_id,
        COALESCE(m.sls_id::varchar, a.sls_id::varchar) AS sls_id,
        c.year,
        c.period,
        c.week,
        MAX(COALESCE(m.visit_date, a.visit_date)) AS max_visit_date,
        SUM(COALESCE(m.count_facing::integer, a.count_facing::integer, 0)) AS total_facing,
        COUNT(DISTINCT COALESCE(m.pcode::varchar, a.pcode::varchar)) AS total_pcode_detected
    FROM raw_ficom_m3.t_rcall_avis_d a
    FULL OUTER JOIN raw_ficom_m3.t_rcall_avis_manual m 
        ON a.distributor_id::varchar = m.distributor_id::varchar
       AND a.outlet_id::varchar = m.outlet_id::varchar
       AND a.pcode::varchar = m.pcode::varchar
       AND a.visit_date = m.visit_date
       AND a.sls_id::varchar = m.sls_id::varchar
    LEFT JOIN spx.m_cycle3 c ON COALESCE(m.visit_date, a.visit_date)::date = c.cdate::date
    GROUP BY 
        COALESCE(m.distributor_id::varchar, a.distributor_id::varchar),
        COALESCE(m.outlet_id::varchar, a.outlet_id::varchar),
        COALESCE(m.sls_id::varchar, a.sls_id::varchar),
        c.year, c.period, c.week
),

-- 2. CTE TRANSAKSI SALES (Agregasi per Week + Store)
cte_sales AS (
    SELECT 
        s.subdist_id::varchar AS distributor_id,
        s.custno::varchar AS outlet_id,
        s.slsno::varchar AS sls_id,
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
        c.year, c.period, c.week
),

-- 3. BASE KONSOLIDASI (FULL OUTER JOIN IR & SALES PER WEEK)
base_activity AS (
    SELECT 
        COALESCE(f.distributor_id, s.distributor_id) AS distributor_id,
        COALESCE(f.outlet_id, s.outlet_id) AS outlet_id,
        COALESCE(f.sls_id, s.sls_id) AS sls_id,
        COALESCE(f.year, s.year) AS year,
        COALESCE(f.period, s.period) AS period,
        COALESCE(f.week, s.week) AS week,
        COALESCE(f.max_visit_date, s.max_inv_date) AS activity_date,
        
        COALESCE(f.total_facing, 0) AS total_facing,
        COALESCE(f.total_pcode_detected, 0) AS total_pcode_detected,
        COALESCE(s.total_inv_qty, 0) AS total_inv_qty,
        COALESCE(s.total_inv_val, 0) AS total_inv_val
    FROM cte_facing f
    FULL OUTER JOIN cte_sales s
        ON f.distributor_id::integer = s.distributor_id::integer
       AND f.outlet_id::integer = s.outlet_id::integer
       AND f.year = s.year
       AND f.period = s.period
       AND f.week = s.week
),

-- 4. CTE GRADING SUMMARY
grading_summary AS (
    SELECT 
        COALESCE(b.distributor_id::varchar, g.distributor_id::varchar) AS distributor_id,
        COALESCE(b.outlet_id::varchar, g.outlet_id::varchar) AS outlet_id,
        COALESCE(b.sls_id::varchar, g.sls_id::varchar) AS sls_id,
        COALESCE(b.visit_date, g.visit_date) AS visit_date,
        COALESCE(b.salesforce_id::varchar, g.salesforce_id::varchar) AS salesforce_id,
        COALESCE(b.grade, g.grade) AS final_grade,
        COALESCE(b.kode_ap::varchar, g.kode_ap::varchar) AS kode_ap,
        COALESCE(b.team_id::varchar, g.team_id::varchar) AS team_id
    FROM raw_ficom_m3.t_grading_ir g
    LEFT JOIN raw_ficom_m3.t_grading_banding b
        ON g.distributor_id::varchar = b.distributor_id::varchar
       AND g.sls_id::varchar = b.sls_id::varchar
       AND g.outlet_id::varchar = b.outlet_id::varchar
       AND g.visit_date = b.visit_date
       AND g.kode_ap::varchar = b.kode_ap::varchar
)

-- MAIN QUERY
SELECT 
    base.year,
    base.period,
    base.week,
    
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
    gr.salesforce_id,
    ms.salesforce_nm,
    mgc.gsalesforce_id,
    mgc.gsalesforce_nm,
    mcs.group_channel_id,
    mcs.group_channel_nm,
    mgc.div_id,
    mgc.div_nm,
    gr.final_grade AS grade,
    gr.kode_ap,
    gr.team_id,
    base.activity_date AS visit_date,

    base.total_facing AS facing_qty,
    base.total_pcode_detected AS pcode_ir_count,
    CASE WHEN base.total_facing > 0 THEN 1 ELSE 0 END AS is_ir_detected,

    base.total_inv_qty AS inv_qty,
    base.total_inv_val AS inv_val,
    CASE WHEN base.total_inv_qty > 0 THEN 1 ELSE 0 END AS is_transaction_exist,

    CASE 
        WHEN base.total_facing > 0 AND base.total_inv_qty > 0 
            THEN '1. IR Terdeteksi & Ada Transaksi'
        WHEN base.total_facing > 0 AND base.total_inv_qty = 0 
            THEN '2. IR Terdeteksi & TANPA Transaksi (Anomali)'
        WHEN base.total_facing = 0 AND base.total_inv_qty > 0 
            THEN '3. IR Tidak Terdeteksi & Ada Transaksi'
        ELSE '4. No IR & No Sales'
    END AS anomaly_status

FROM base_activity base

LEFT JOIN raw_ficom_m3.v_salesman_hierarchy b 
    ON base.sls_id::varchar = b.sls_id::varchar  
   AND base.distributor_id::varchar = b.distributor_id::varchar

LEFT JOIN grading_summary gr
    ON base.distributor_id::varchar = gr.distributor_id::varchar
   AND base.outlet_id::varchar = gr.outlet_id::varchar
   AND base.sls_id::varchar = gr.sls_id::varchar
   AND base.activity_date = gr.visit_date

LEFT JOIN raw_ficom_m3.m_distributor md 
    ON base.distributor_id::varchar = md.distributor_id::varchar

LEFT JOIN raw_ficom_m3.m_customer mc 
    ON base.distributor_id::varchar = mc.distributor_id::varchar 
   AND base.outlet_id::varchar = mc.cust_id::varchar 

LEFT JOIN raw_ficom_m3.m_salesforce ms 
    ON gr.salesforce_id::varchar = ms.salesforce_id::varchar 

LEFT JOIN latest_fcustsls vfs 
    ON base.distributor_id::varchar = vfs.distributor_id::varchar 
   AND base.outlet_id::varchar = vfs.cust_id::varchar 
   AND vfs.rn = 1

LEFT JOIN raw_ficom_m3.m_group_channels mcs 
    ON vfs.channel_id::varchar = mcs.channel_id::varchar 

LEFT JOIN raw_ficom_m3.m_mapping_group_salesforce mgc 
    ON gr.salesforce_id::varchar = mgc.salesforce_id::varchar