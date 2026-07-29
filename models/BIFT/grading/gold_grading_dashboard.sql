{{
  config(
    materialized = 'incremental',
    unique_key = ['distributor_id', 'outlet_id', 'visit_date', 'sls_id', 'kode_ap'],
    on_schema_change = 'append_new_columns',
    indexes = [
      {'columns': ['distributor_id', 'outlet_id', 'visit_date']},
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

-- 1. CTE FACING IR (AI + MANUAL BANDING)
cte_facing AS (
    SELECT 
        COALESCE(m.distributor_id::varchar, a.distributor_id::varchar) AS distributor_id,
        COALESCE(m.outlet_id::varchar, a.outlet_id::varchar) AS outlet_id,
        COALESCE(m.sls_id::varchar, a.sls_id::varchar) AS sls_id,
        COALESCE(m.visit_date, a.visit_date) AS visit_date,
        SUM(COALESCE(m.count_facing::integer, a.count_facing::integer, 0)) AS total_facing,
        COUNT(DISTINCT COALESCE(m.pcode::varchar, a.pcode::varchar)) AS total_pcode_detected
    FROM raw_ficom_m3.t_rcall_avis_d a
    FULL OUTER JOIN raw_ficom_m3.t_rcall_avis_manual m 
        ON a.distributor_id::varchar = m.distributor_id::varchar
       AND a.outlet_id::varchar = m.outlet_id::varchar
       AND a.pcode::varchar = m.pcode::varchar
       AND a.visit_date = m.visit_date
       AND a.sls_id::varchar = m.sls_id::varchar
    {% if is_incremental() %}
      WHERE COALESCE(m.visit_date, a.visit_date) >= (SELECT MAX(visit_date) - INTERVAL '7 days' FROM {{ this }})
    {% endif %}
    GROUP BY 
        COALESCE(m.distributor_id::varchar, a.distributor_id::varchar),
        COALESCE(m.outlet_id::varchar, a.outlet_id::varchar),
        COALESCE(m.sls_id::varchar, a.sls_id::varchar),
        COALESCE(m.visit_date, a.visit_date)
),

-- 2. CTE TRANSAKSI SALES
cte_sales AS (
    SELECT 
        s.subdist_id::varchar AS distributor_id,
        s.custno::varchar AS outlet_id,
        s.inv_date,
        SUM(COALESCE(s.inv_qty::numeric, 0)) AS total_inv_qty,
        SUM(COALESCE(s.inv_val::numeric, 0)) AS total_inv_val
    FROM raw_ho.vfsales_det s
    WHERE (COALESCE(s.inv_qty::numeric, 0) > 0 OR COALESCE(s.inv_val::numeric, 0) > 0)
    {% if is_incremental() %}
      AND s.inv_date >= (SELECT MAX(visit_date) - INTERVAL '7 days' FROM {{ this }})
    {% endif %}
    GROUP BY s.subdist_id::varchar, s.custno::varchar, s.inv_date
)

SELECT 
    mc3.year,
    mc3.period,
    mc3.week,
    
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
    b.sls_id,
    b.distributor_id,

    -- Master Data & Grading
    md.distributor_nm,
    COALESCE(tgb.outlet_id, a.outlet_id) AS outlet_id,
    mc.cust_nm,
    mc.city,
    COALESCE(tgb.salesforce_id, a.salesforce_id) AS salesforce_id,
    ms.salesforce_nm,
    mgc.gsalesforce_id,
    mgc.gsalesforce_nm,
    mcs.group_channel_id,
    mcs.group_channel_nm,
    mgc.div_id,
    mgc.div_nm,
    COALESCE(tgb.grade, a.grade) AS grade,
    COALESCE(tgb.kode_ap, a.kode_ap) AS kode_ap,
    COALESCE(tgb.team_id, a.team_id) AS team_id,
    COALESCE(tgb.visit_date, a.visit_date) AS visit_date,

    -- Metric Facing (IR)
    COALESCE(f.total_facing, 0) AS facing_qty,
    COALESCE(f.total_pcode_detected, 0) AS pcode_ir_count,
    CASE WHEN COALESCE(f.total_facing, 0) > 0 THEN 1 ELSE 0 END AS is_ir_detected,

    -- Metric Transaksi (vfsales_det)
    COALESCE(sls.total_inv_qty, 0) AS inv_qty,
    COALESCE(sls.total_inv_val, 0) AS inv_val,
    CASE WHEN COALESCE(sls.total_inv_qty, 0) > 0 THEN 1 ELSE 0 END AS is_transaction_exist,

    -- Sense Check Status
    CASE 
        WHEN COALESCE(f.total_facing, 0) > 0 AND COALESCE(sls.total_inv_qty, 0) > 0 
            THEN '1. IR Terdeteksi & Ada Transaksi'
        WHEN COALESCE(f.total_facing, 0) > 0 AND COALESCE(sls.total_inv_qty, 0) = 0 
            THEN '2. IR Terdeteksi & TANPA Transaksi (Anomali)'
        WHEN COALESCE(f.total_facing, 0) = 0 AND COALESCE(sls.total_inv_qty, 0) > 0 
            THEN '3. IR Tidak Terdeteksi & Ada Transaksi'
        ELSE '4. No IR & No Sales'
    END AS anomaly_status

FROM raw_ficom_m3.v_salesman_hierarchy b 

LEFT JOIN raw_ficom_m3.t_grading_ir a  
    ON a.sls_id::varchar = b.sls_id::varchar  
   AND a.distributor_id::varchar = b.distributor_id::varchar
   {% if is_incremental() %}
     AND a.visit_date >= (SELECT MAX(visit_date) - INTERVAL '7 days' FROM {{ this }})
   {% endif %}

LEFT JOIN raw_ficom_m3.t_grading_banding tgb 
    ON a.distributor_id::varchar = tgb.distributor_id::varchar 
   AND a.sls_id::varchar = tgb.sls_id::varchar 
   AND a.team_id::varchar = tgb.team_id::varchar 
   AND a.salesforce_id::varchar = tgb.salesforce_id::varchar 
   AND a.outlet_id::varchar = tgb.outlet_id::varchar 
   AND a.visit_date = tgb.visit_date 
   AND a.kode_ap::varchar = tgb.kode_ap::varchar

LEFT JOIN raw_ficom_m3.m_distributor md 
    ON COALESCE(tgb.distributor_id::varchar, a.distributor_id::varchar) = md.distributor_id::varchar

LEFT JOIN raw_ficom_m3.m_customer mc 
    ON COALESCE(tgb.distributor_id::varchar, a.distributor_id::varchar) = mc.distributor_id::varchar 
   AND COALESCE(tgb.outlet_id::varchar, a.outlet_id::varchar) = mc.cust_id::varchar 

LEFT JOIN raw_ficom_m3.m_salesforce ms 
    ON COALESCE(tgb.salesforce_id::varchar, a.salesforce_id::varchar) = ms.salesforce_id::varchar 

LEFT JOIN latest_fcustsls vfs 
    ON COALESCE(tgb.distributor_id::varchar, a.distributor_id::varchar) = vfs.distributor_id::varchar 
   AND COALESCE(tgb.outlet_id::varchar, a.outlet_id::varchar) = vfs.cust_id::varchar 
   AND vfs.rn = 1

LEFT JOIN raw_ficom_m3.m_group_channels mcs 
    ON vfs.channel_id::varchar = mcs.channel_id::varchar 

LEFT JOIN raw_ficom_m3.m_mapping_group_salesforce mgc 
    ON a.salesforce_id::varchar = mgc.salesforce_id::varchar

LEFT JOIN spx.m_cycle3 mc3 
    ON COALESCE(tgb.visit_date, a.visit_date) = mc3.cdate

-- JOIN METRIC FACING & TRANSAKSI
LEFT JOIN cte_facing f
    ON COALESCE(tgb.distributor_id::varchar, a.distributor_id::varchar) = f.distributor_id
   AND COALESCE(tgb.outlet_id::varchar, a.outlet_id::varchar) = f.outlet_id
   AND COALESCE(tgb.sls_id::varchar, a.sls_id::varchar) = f.sls_id
   AND COALESCE(tgb.visit_date, a.visit_date) = f.visit_date

LEFT JOIN cte_sales sls
    ON COALESCE(tgb.distributor_id::varchar, a.distributor_id::varchar) = sls.distributor_id
   AND COALESCE(tgb.outlet_id::varchar, a.outlet_id::varchar) = sls.outlet_id
   AND COALESCE(tgb.visit_date, a.visit_date) = sls.inv_date