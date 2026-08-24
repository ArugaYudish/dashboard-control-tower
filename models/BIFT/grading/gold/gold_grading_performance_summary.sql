{{
    config(
        materialized = 'table',
        schema = 'bift',
        alias = 'gold_grading_performance_summary',
        indexes = [
            {'columns': ['year', 'period', 'week']},
            {'columns': ['report_date', 'visit_date', 'inv_date']},
            {'columns': ['source_schema', 'gdiv_id']},
            {'columns': ['sd_id', 'rsm_id', 'ss_id']},
            {'columns': ['distributor_id', 'sls_id', 'outlet_id']},
            {'columns': ['pcode']},
            {'columns': ['grade']},
            {'columns': ['anomaly_status']}
        ]
    )
}}

WITH 
----------------------------------------------------------------------
-- 0. KAMUS MASTER PRODUK & SUBBRAND (raw_ho.fmaster + dim_mapping_subbrand)
----------------------------------------------------------------------
cte_product_gdiv AS (
    SELECT DISTINCT
        p.pcode::varchar            AS pcode,
        p.pcodename::varchar        AS pcode_nm,
        mms.subbrand_id::varchar    AS subbrand_id,
        mms.subbrand_nm::varchar    AS subbrand_nm,
        mms.cat_id::varchar         AS cat_id,
        mms.cat_nm::varchar         AS cat_nm,
        mms.gdiv_id::varchar        AS gdiv_id,
        mms.gdiv_nm::varchar        AS gdiv_nm,
        mms.div_id::varchar         AS div_id,
        mms.div_nm::varchar         AS div_nm
    FROM raw_ho.fmaster p
    LEFT JOIN bift.dim_mapping_subbrand mms 
        ON (COALESCE(p.prlin::varchar, '') || COALESCE(p.brand::varchar, '') || COALESCE(p.sbra1::varchar, '')) = mms.subbrand_id::varchar
),

----------------------------------------------------------------------
-- 1. MASTER SALESMAN HIERARKI (DARI BRONZE SALESMAN HIERARCHY)
----------------------------------------------------------------------
cte_master_salesman AS (
    SELECT DISTINCT
        source_schema::varchar      AS source_schema,
        gdiv_id::varchar            AS gdiv_id,
        gdiv_nm::varchar            AS gdiv_nm,
        distributor_id::varchar     AS distributor_id,
        distributor_nm::varchar     AS distributor_nm,
        sls_id::varchar             AS sls_id,
        sls_nm::varchar             AS sls_nm,
        sd_id::varchar              AS sd_id,
        sd_nm::varchar              AS sd_nm,
        nsm_id::varchar             AS nsm_id,
        nsm_nm::varchar             AS nsm_nm,
        grsm_id::varchar            AS grsm_id,
        grsm_nm::varchar            AS grsm_nm,
        rsm_id::varchar             AS rsm_id,
        rsm_nm::varchar             AS rsm_nm,
        ss_id::varchar              AS ss_id,
        ss_nm::varchar              AS ss_nm
    FROM bift.bronze_salesman_hierarchy
),

----------------------------------------------------------------------
-- 2. MASTER OUTLET (DARI SILVER OA PERIODE 7)
----------------------------------------------------------------------
cte_master_outlet AS (
    SELECT DISTINCT ON (distributor_id, cust_id)
        source_schema::varchar      AS source_schema,
        distributor_id::varchar     AS distributor_id,
        cust_id::varchar            AS outlet_id,
        cust_nm::varchar            AS cust_nm,
        kabupaten_name::varchar     AS city,
        channel_id::varchar         AS channel_id,
        channel_nm::varchar         AS channel_nm,
        group_channel_id::varchar   AS group_channel_id,
        group_channel_nm::varchar   AS group_channel_nm,
        salesforce_id::varchar      AS salesforce_id,
        salesforce_nm::varchar      AS salesforce_nm,
        gsalesforce1_id::varchar    AS gsalesforce_id,
        gsalesforce1_nm::varchar    AS gsalesforce_nm
    FROM {{ ref('silver_oa_performance') }}
    WHERE tahun = 2026 AND periode = 7 AND is_transaction = 0
    ORDER BY distributor_id, cust_id
),

----------------------------------------------------------------------
-- 3. BACKBONE KEGIATAN HARIAN (TRIAL 13-14 JULI 2026)
----------------------------------------------------------------------
cte_backbone AS (
    -- Sumber 1: Transaksi SFA Harian
    SELECT 
        source_schema::varchar      AS source_schema,
        gdiv_id::varchar            AS gdiv_id,
        distributor_id::varchar     AS distributor_id,
        sls_id::varchar             AS sls_id,
        cust_id::varchar            AS outlet_id,
        pcode::varchar              AS pcode,
        COALESCE(date, inv_date)    AS activity_date,
        tahun::numeric              AS tahun,
        periode::numeric            AS periode,
        week::numeric               AS week
    FROM {{ ref('silver_oa_performance') }}
    WHERE is_transaction = 1
      AND COALESCE(date, inv_date) >= '2026-07-13' AND COALESCE(date, inv_date) <= '2026-07-14'

    UNION

    -- Sumber 2: Kunjungan Foto IR Display
    SELECT 
        COALESCE(a.source_schema::varchar, 'spx') AS source_schema,
        COALESCE(pg.gdiv_id, 'UNKNOWN_GDIV')      AS gdiv_id,
        a.distributor_id::varchar                 AS distributor_id,
        a.sls_id::varchar                         AS sls_id,
        a.outlet_id::varchar                      AS outlet_id,
        a.pcode::varchar                          AS pcode,
        a.visit_date::date                        AS activity_date,
        2026::numeric                             AS tahun,
        7::numeric                                AS periode,
        28::numeric                               AS week
    FROM bift.bronze_rcall_avis_d a
    LEFT JOIN cte_product_gdiv pg ON a.pcode::varchar = pg.pcode
    WHERE a.visit_date >= '2026-07-13' AND a.visit_date <= '2026-07-14'

    UNION

    -- Sumber 3: Toko CB Pasif (Master Bulanan)
    SELECT 
        source_schema::varchar      AS source_schema,
        gdiv_id::varchar            AS gdiv_id,
        distributor_id::varchar     AS distributor_id,
        sls_id::varchar             AS sls_id,
        cust_id::varchar            AS outlet_id,
        NULL::varchar               AS pcode,
        NULL::date                  AS activity_date,
        tahun::numeric              AS tahun,
        periode::numeric            AS periode,
        week::numeric               AS week
    FROM {{ ref('silver_oa_performance') }}
    WHERE is_transaction = 0
      AND tahun = 2026 AND periode = 7
),

----------------------------------------------------------------------
-- 4. DEDUP BACKBONE
----------------------------------------------------------------------
cte_unique_activity AS (
    SELECT 
        source_schema,
        gdiv_id,
        distributor_id,
        sls_id,
        outlet_id,
        pcode,
        activity_date,
        tahun,
        periode,
        week
    FROM cte_backbone
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),

----------------------------------------------------------------------
-- 5. AGREGASI GRADING HARIAN
----------------------------------------------------------------------
cte_grading_daily AS (
    SELECT 
        g.source_schema::varchar AS source_schema,
        g.distributor_id::varchar AS distributor_id,
        g.sls_id::varchar AS sls_id,
        g.outlet_id::varchar AS outlet_id,
        g.visit_date::date AS visit_date,
        MAX(COALESCE(b.grade::varchar, g.grade::varchar)) AS final_grade,
        MAX(COALESCE(b.kode_ap::varchar, g.kode_ap::varchar)) AS kode_ap
    FROM bift.bronze_grading_ir g
    LEFT JOIN bift.bronze_grading_banding b
        ON g.source_schema::varchar  = b.source_schema::varchar
       AND g.distributor_id::varchar = b.distributor_id::varchar
       AND g.outlet_id::varchar      = b.outlet_id::varchar
       AND g.sls_id::varchar         = b.sls_id::varchar
       AND g.kode_ap::varchar        = b.kode_ap::varchar
       AND g.visit_date::date        = b.visit_date::date
    WHERE g.visit_date >= '2026-07-13' AND g.visit_date <= '2026-07-14'
    GROUP BY 1, 2, 3, 4, 5
),

----------------------------------------------------------------------
-- 6. AGREGASI IR DISPLAY
----------------------------------------------------------------------
cte_ir_daily AS (
    SELECT 
        a.source_schema::varchar AS source_schema,
        a.distributor_id::varchar AS distributor_id,
        a.sls_id::varchar AS sls_id,
        a.outlet_id::varchar AS outlet_id,
        a.pcode::varchar AS pcode,
        a.visit_date::date AS visit_date,
        MAX(a.kode_ap::varchar) AS kode_ap,
        SUM(COALESCE(m.count_facing::integer, a.count_facing::integer, 0)) AS total_facing,
        1 AS is_ir_detected
    FROM bift.bronze_rcall_avis_d a
    LEFT JOIN (
        SELECT 
            source_schema::varchar AS source_schema,
            distributor_id::varchar AS distributor_id, 
            outlet_id::varchar AS outlet_id,
            sls_id::varchar AS sls_id, 
            kode_ap::varchar AS kode_ap, 
            pcode::varchar AS pcode, 
            visit_date::date AS visit_date,
            MAX(count_facing::integer) AS count_facing
        FROM bift.bronze_rcall_avis_manual
        WHERE visit_date >= '2026-07-13' AND visit_date <= '2026-07-14'
        GROUP BY 1, 2, 3, 4, 5, 6, 7
    ) m 
        ON a.source_schema::varchar  = m.source_schema::varchar
       AND a.distributor_id::varchar = m.distributor_id 
       AND a.outlet_id::varchar      = m.outlet_id
       AND a.sls_id::varchar         = m.sls_id 
       AND a.kode_ap::varchar        = m.kode_ap
       AND a.pcode::varchar          = m.pcode 
       AND a.visit_date::date        = m.visit_date
    WHERE a.visit_date >= '2026-07-13' AND a.visit_date <= '2026-07-14'
    GROUP BY 1, 2, 3, 4, 5, 6
),

----------------------------------------------------------------------
-- 7. AGREGASI TRANSAKSI SALES SFA
----------------------------------------------------------------------
cte_sales_daily AS (
    SELECT 
        source_schema::varchar AS source_schema,
        gdiv_id::varchar AS gdiv_id,
        distributor_id::varchar AS distributor_id,
        sls_id::varchar AS sls_id,
        cust_id::varchar AS outlet_id,
        pcode::varchar AS pcode,
        COALESCE(date, inv_date) AS sales_date,
        MAX(pcode_nm::varchar) AS pcode_nm,
        MAX(subbrand_id::varchar) AS subbrand_id,
        MAX(subbrand_nm::varchar) AS subbrand_nm,
        MAX(cat_id::varchar) AS cat_id,
        MAX(cat_nm::varchar) AS cat_nm,
        MAX(div_id::varchar) AS div_id,
        MAX(div_nm::varchar) AS div_nm,
        SUM(inv_qty) AS total_inv_qty,
        SUM(inv_val) AS total_inv_val
    FROM {{ ref('silver_oa_performance') }}
    WHERE is_transaction = 1
      AND COALESCE(date, inv_date) >= '2026-07-13' AND COALESCE(date, inv_date) <= '2026-07-14'
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),

----------------------------------------------------------------------
-- 8. TARGET NMRC HARIAN
----------------------------------------------------------------------
cte_nmrc_daily AS (
    SELECT 
        source_schema::varchar AS source_schema,
        distributor_id::varchar AS distributor_id,
        sls_id::varchar AS sls_id,
        tgl::date AS report_date,
        MAX(tgt_call::numeric) AS tgt_call,
        MAX(tcall_glb::numeric) AS tcall_glb,
        MAX(rcall_kpl::numeric) AS rcall_kpl,
        MAX(ec_kpl::numeric) AS ec_kpl
    FROM bift.bronze_nmrc_subdetail
    WHERE tgl >= '2026-07-13' AND tgl <= '2026-07-14'
    GROUP BY 1, 2, 3, 4
)

----------------------------------------------------------------------
-- MAIN SELECT
----------------------------------------------------------------------
SELECT 
    b.tahun AS year,
    b.periode AS period,
    b.week,
    
    -- DATES
    b.activity_date AS report_date,
    gst.visit_date,
    sal.sales_date AS inv_date,
    
    -- HIERARKI SD, NSM, GRSM, RSM, SS
    ms.sd_id,
    ms.sd_nm,
    ms.nsm_id,
    ms.nsm_nm,
    ms.grsm_id,
    ms.grsm_nm,
    ms.rsm_id,
    ms.rsm_nm,
    ms.ss_id,
    ms.ss_nm,
    
    -- DISTRIBUTOR & OUTLET
    b.distributor_id,
    ms.distributor_nm,
    b.outlet_id,
    mo.cust_nm,
    mo.city,
    
    -- SALESMAN
    b.sls_id,
    ms.sls_nm,
    
    -- PRODUK & KATEGORI
    b.pcode,
    COALESCE(sal.pcode_nm, pg.pcode_nm) AS pcode_nm,
    COALESCE(sal.subbrand_id, pg.subbrand_id) AS subbrand_id,
    COALESCE(sal.subbrand_nm, pg.subbrand_nm) AS subbrand_nm,
    COALESCE(sal.cat_id, pg.cat_id) AS cat_id,
    COALESCE(sal.cat_nm, pg.cat_nm) AS cat_nm,
    
    -- SALESFORCE & CHANNEL
    mo.salesforce_id,
    mo.salesforce_nm,
    mo.gsalesforce_id,
    mo.gsalesforce_nm,
    mo.group_channel_id,
    mo.group_channel_nm,
    COALESCE(sal.div_id, pg.div_id) AS div_id,
    COALESCE(sal.div_nm, pg.div_nm) AS div_nm,
    
    -- GRADING & DISPLAY
    COALESCE(gst.final_grade, 'UNVISITED / UNGRADED') AS grade,
    COALESCE(ir.kode_ap, gst.kode_ap, 'N/A') AS kode_ap,
    COALESCE(ir.total_facing, 0) AS facing_qty,
    
    -- METRIK PEMBAGI (DENOMINATOR)
    1 AS is_cb_master,
    COALESCE(nm.tgt_call, 0) AS tgt_call_nmrc,
    COALESCE(nm.tcall_glb, 0) AS tcall_glb_nmrc,
    COALESCE(nm.rcall_kpl, 0) AS rcall_kpl_nmrc,
    COALESCE(nm.ec_kpl, 0) AS ec_kpl_nmrc,
    
    -- TRANSAKSI & DETEKSI IR
    COALESCE(ir.is_ir_detected, 0) AS is_ir_detected,
    COALESCE(sal.total_inv_qty, 0) AS inv_qty,
    COALESCE(sal.total_inv_val, 0) AS inv_val,
    
    -- EFFECTIVE CALL (EC) INDICATORS
    CASE WHEN COALESCE(sal.total_inv_qty, 0) > 0 THEN 1 ELSE 0 END AS is_ec_transaction,
    CASE WHEN COALESCE(ir.is_ir_detected, 0) = 1 THEN 1 ELSE 0 END AS is_ec_display,
    CASE WHEN (COALESCE(sal.total_inv_qty, 0) > 0 AND COALESCE(ir.is_ir_detected, 0) = 1) THEN 1 ELSE 0 END AS is_ec_avis,
    
    -- ANOMALY STATUS
    CASE 
        WHEN COALESCE(ir.is_ir_detected, 0) = 1 AND COALESCE(sal.total_inv_qty, 0) > 0 
            THEN '1. IR Terdeteksi & Ada Transaksi'
        WHEN COALESCE(ir.is_ir_detected, 0) = 1 AND COALESCE(sal.total_inv_qty, 0) = 0 
            THEN '2. IR Terdeteksi & TANPA Transaksi (Anomali IR)'
        WHEN COALESCE(ir.is_ir_detected, 0) = 0 AND COALESCE(sal.total_inv_qty, 0) > 0 
            THEN '3. Tidak Ada di Tabel IR & Ada Transaksi (Uncovered Sales)'
        ELSE '4. No IR & No Sales'
    END AS anomaly_status

FROM cte_unique_activity b

-- 1. JOIN MASTER OUTLET
LEFT JOIN cte_master_outlet mo
    ON b.distributor_id = mo.distributor_id
   AND b.outlet_id      = mo.outlet_id

-- 2. JOIN MASTER SALESMAN (KUNCI GDIV + DISTRIBUTOR + SLS)
LEFT JOIN cte_master_salesman ms
    ON b.gdiv_id        = ms.gdiv_id
   AND b.distributor_id = ms.distributor_id
   AND b.sls_id         = ms.sls_id

-- 3. JOIN TRANSAKSI SALES
LEFT JOIN cte_sales_daily sal
    ON b.gdiv_id         = sal.gdiv_id
   AND b.distributor_id  = sal.distributor_id
   AND b.sls_id          = sal.sls_id
   AND b.outlet_id       = sal.outlet_id
   AND b.pcode           = sal.pcode
   AND b.activity_date   = sal.sales_date

-- 4. JOIN MASTER PRODUK INFO
LEFT JOIN cte_product_gdiv pg
    ON b.pcode = pg.pcode

-- 5. JOIN GRADE TOKO
LEFT JOIN cte_grading_daily gst
    ON b.distributor_id  = gst.distributor_id
   AND b.sls_id          = gst.sls_id
   AND b.outlet_id       = gst.outlet_id
   AND b.activity_date   = gst.visit_date

-- 6. JOIN IR DISPLAY
LEFT JOIN cte_ir_daily ir
    ON b.distributor_id  = ir.distributor_id
   AND b.sls_id          = ir.sls_id
   AND b.outlet_id       = ir.outlet_id
   AND b.pcode           = ir.pcode
   AND b.activity_date   = ir.visit_date

-- 7. JOIN TARGET NMRC
LEFT JOIN cte_nmrc_daily nm
    ON b.distributor_id  = nm.distributor_id
   AND b.sls_id          = nm.sls_id
   AND b.activity_date   = nm.report_date