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
-- 0. KAMUS MASTER PRODUK & SUBBRAND (DARI raw_ho.fmaster)
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
    LEFT JOIN {{ source('bift', 'dim_mapping_subbrand') }} mms 
        ON CONCAT(
            COALESCE(p.prlin::varchar, ''), 
            COALESCE(p.brand::varchar, ''), 
            COALESCE(p.sbra1::varchar, '')
        ) = mms.subbrand_id::varchar
),

----------------------------------------------------------------------
-- 1. MASTER SALESMAN HIERARKI (DARI SILVER OA)
----------------------------------------------------------------------
cte_master_salesman AS (
    SELECT DISTINCT ON (source_schema, distributor_id, sls_id)
        source_schema,
        gdiv_id,
        gdiv_nm,
        distributor_id,
        distributor_nm,
        sls_id,
        sls_nm,
        sd_id, sd_nm,
        nsm_id, nsm_nm,
        grsm_id, grsm_nm,
        rsm_id, rsm_nm,
        ss_id, ss_nm
    FROM {{ ref('silver_oa_performance') }}
    ORDER BY source_schema, distributor_id, sls_id, tahun DESC, periode DESC
),

----------------------------------------------------------------------
-- 2. BACKBONE KEGIATAN HARIAN (DIBATASI PERIODE 6 & 7 TAHUN 2026)
----------------------------------------------------------------------
cte_backbone AS (
    -- Sumber 1: Transaksi SFA Harian
    SELECT 
        source_schema,
        gdiv_id,
        distributor_id,
        sls_id,
        cust_id AS outlet_id,
        pcode,
        COALESCE(date, inv_date) AS activity_date,
        tahun,
        periode,
        week
    FROM {{ ref('silver_oa_performance') }}
    WHERE is_transaction = 1
      AND tahun = 2026 AND periode IN (6, 7)

    UNION

    -- Sumber 2: Kunjungan Foto IR Display
    SELECT 
        a.source_schema::varchar AS source_schema,
        COALESCE(pg.gdiv_id, 'UNKNOWN_GDIV') AS gdiv_id,
        a.distributor_id::varchar AS distributor_id,
        a.sls_id::varchar AS sls_id,
        a.outlet_id::varchar AS outlet_id,
        a.pcode::varchar AS pcode,
        a.visit_date::date AS activity_date,
        c.year AS tahun,
        c.period AS periode,
        c.week AS week
    FROM {{ source('bift', 'bronze_rcall_avis_d') }} a
    LEFT JOIN spx.m_cycle3 c 
        ON a.visit_date::date = c.cdate::date
    LEFT JOIN cte_product_gdiv pg 
        ON a.pcode::varchar = pg.pcode
    WHERE c.year = 2026 AND c.period IN (6, 7)

    UNION

    -- Sumber 3: Toko CB Pasif (Master Bulanan)
    SELECT 
        source_schema,
        gdiv_id,
        distributor_id,
        sls_id,
        cust_id AS outlet_id,
        NULL AS pcode,
        NULL AS activity_date,
        tahun,
        periode,
        week
    FROM {{ ref('silver_oa_performance') }}
    WHERE is_transaction = 0
      AND tahun = 2026 AND periode IN (6, 7)
),

----------------------------------------------------------------------
-- 3. DEDUP BACKBONE (1 BARIS UNIK: GDIV + DIST + SLS + OUTLET + PCODE + TGL)
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
-- 4. AGREGASI GRADING HARIAN (DIBATASI PERIODE 6 & 7)
----------------------------------------------------------------------
cte_grading_daily AS (
    SELECT 
        g.source_schema::varchar AS source_schema,
        COALESCE(ms.gdiv_id, 'UNKNOWN_GDIV') AS gdiv_id,
        g.distributor_id::varchar AS distributor_id,
        g.sls_id::varchar AS sls_id,
        g.outlet_id::varchar AS outlet_id,
        g.visit_date::date AS visit_date,
        MAX(COALESCE(b.grade, g.grade)) AS final_grade,
        MAX(COALESCE(b.kode_ap::varchar, g.kode_ap::varchar)) AS kode_ap
    FROM {{ source('bift', 'bronze_grading_ir') }} g
    LEFT JOIN spx.m_cycle3 c 
        ON g.visit_date::date = c.cdate::date
    LEFT JOIN cte_master_salesman ms
        ON COALESCE(g.source_schema::varchar, '') = COALESCE(ms.source_schema::varchar, '')
       AND g.distributor_id::varchar              = ms.distributor_id::varchar
       AND g.sls_id::varchar                      = ms.sls_id::varchar
    LEFT JOIN {{ source('bift', 'bronze_grading_banding') }} b
        ON COALESCE(g.source_schema::varchar, '') = COALESCE(b.source_schema::varchar, '')
       AND g.distributor_id::varchar              = b.distributor_id::varchar
       AND g.outlet_id::varchar                   = b.outlet_id::varchar
       AND g.sls_id::varchar                      = b.sls_id::varchar
       AND g.kode_ap::varchar                     = b.kode_ap::varchar
       AND COALESCE(g.team_id::varchar, '')       = COALESCE(b.team_id::varchar, '')
       AND COALESCE(g.salesforce_id::varchar, '') = COALESCE(b.salesforce_id::varchar, '')
       AND g.visit_date::date                     = b.visit_date::date
    WHERE c.year = 2026 AND c.period IN (6, 7)
    GROUP BY 1, 2, 3, 4, 5, 6
),

----------------------------------------------------------------------
-- 5. AGREGASI IR DISPLAY (DIBATASI PERIODE 6 & 7)
----------------------------------------------------------------------
cte_ir_daily AS (
    SELECT 
        a.source_schema::varchar AS source_schema,
        COALESCE(pg.gdiv_id, 'UNKNOWN_GDIV') AS gdiv_id,
        a.distributor_id::varchar AS distributor_id,
        a.sls_id::varchar AS sls_id,
        a.outlet_id::varchar AS outlet_id,
        a.pcode::varchar AS pcode,
        a.visit_date::date AS visit_date,
        MAX(a.kode_ap::varchar) AS kode_ap,
        SUM(COALESCE(m.count_facing, a.count_facing::integer, 0)) AS total_facing,
        1 AS is_ir_detected
    FROM {{ source('bift', 'bronze_rcall_avis_d') }} a
    LEFT JOIN spx.m_cycle3 c 
        ON a.visit_date::date = c.cdate::date
    LEFT JOIN cte_product_gdiv pg
        ON a.pcode::varchar = pg.pcode
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
        FROM {{ source('bift', 'bronze_rcall_avis_manual') }}
        GROUP BY 1, 2, 3, 4, 5, 6, 7
    ) m 
        ON COALESCE(a.source_schema::varchar, '') = COALESCE(m.source_schema::varchar, '')
       AND a.distributor_id::varchar              = m.distributor_id 
       AND a.outlet_id::varchar                   = m.outlet_id
       AND a.sls_id::varchar                      = m.sls_id 
       AND a.kode_ap::varchar                     = m.kode_ap
       AND a.pcode::varchar                       = m.pcode 
       AND a.visit_date::date                     = m.visit_date
    WHERE c.year = 2026 AND c.period IN (6, 7)
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),

----------------------------------------------------------------------
-- 6. AGREGASI TRANSAKSI SALES SFA (DIBATASI PERIODE 6 & 7)
----------------------------------------------------------------------
cte_sales_daily AS (
    SELECT 
        source_schema,
        gdiv_id,
        distributor_id,
        sls_id,
        cust_id AS outlet_id,
        pcode,
        COALESCE(date, inv_date) AS sales_date,
        MAX(pcode_nm) AS pcode_nm,
        MAX(subbrand_id) AS subbrand_id,
        MAX(subbrand_nm) AS subbrand_nm,
        MAX(cat_id) AS cat_id,
        MAX(cat_nm) AS cat_nm,
        MAX(div_id) AS div_id,
        MAX(div_nm) AS div_nm,
        SUM(inv_qty) AS total_inv_qty,
        SUM(inv_val) AS total_inv_val
    FROM {{ ref('silver_oa_performance') }}
    WHERE is_transaction = 1
      AND tahun = 2026 AND periode IN (6, 7)
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),

----------------------------------------------------------------------
-- 7. MASTER OUTLET (MURNI LEVEL TOKO)
----------------------------------------------------------------------
cte_master_outlet AS (
    SELECT DISTINCT ON (source_schema, distributor_id, cust_id)
        source_schema,
        distributor_id,
        cust_id AS outlet_id,
        cust_nm,
        kabupaten_name AS city,
        channel_id, channel_nm,
        group_channel_id, group_channel_nm,
        salesforce_id, salesforce_nm,
        gsalesforce1_id AS gsalesforce_id,
        gsalesforce1_nm AS gsalesforce_nm
    FROM {{ ref('silver_oa_performance') }}
    ORDER BY source_schema, distributor_id, cust_id, tahun DESC, periode DESC
),

----------------------------------------------------------------------
-- 8. TARGET NMRC HARIAN (DIBATASI PERIODE 6 & 7)
----------------------------------------------------------------------
cte_nmrc_daily AS (
    SELECT 
        n.source_schema::varchar AS source_schema,
        COALESCE(ms.gdiv_id, 'UNKNOWN_GDIV') AS gdiv_id,
        n.distributor_id::varchar AS distributor_id,
        n.sls_id::varchar AS sls_id,
        n.tgl::date AS report_date,
        MAX(n.tgt_call::numeric) AS tgt_call,
        MAX(n.tcall_glb::numeric) AS tcall_glb,
        MAX(n.rcall_kpl::numeric) AS rcall_kpl,
        MAX(n.ec_kpl::numeric) AS ec_kpl
    FROM {{ source('bift', 'bronze_nmrc_subdetail') }} n
    LEFT JOIN cte_master_salesman ms
        ON COALESCE(n.source_schema::varchar, '') = COALESCE(ms.source_schema::varchar, '')
       AND n.distributor_id::varchar              = ms.distributor_id::varchar
       AND n.sls_id::varchar                      = ms.sls_id::varchar
    WHERE n.tahun = 2026 AND n.periode IN (6, 7)
    GROUP BY 1, 2, 3, 4, 5
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
    
    -- ANOMALY STATUS / KUADRAN PRODUKTIVITAS
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
    ON b.source_schema  = mo.source_schema
   AND b.distributor_id = mo.distributor_id
   AND b.outlet_id      = mo.outlet_id

-- 2. JOIN MASTER SALESMAN (TERKUNCI GDIV)
LEFT JOIN cte_master_salesman ms
    ON b.source_schema  = ms.source_schema
   AND b.gdiv_id        = ms.gdiv_id
   AND b.distributor_id = ms.distributor_id
   AND b.sls_id         = ms.sls_id

-- 3. JOIN TRANSAKSI SALES (TERKUNCI GDIV)
LEFT JOIN cte_sales_daily sal
    ON b.source_schema   = sal.source_schema
   AND b.gdiv_id         = sal.gdiv_id
   AND b.distributor_id  = sal.distributor_id
   AND b.sls_id          = sal.sls_id
   AND b.outlet_id       = sal.outlet_id
   AND b.pcode           = sal.pcode
   AND b.activity_date   = sal.sales_date

-- 4. JOIN MASTER PRODUK INFO DARI fmaster & subbrand
LEFT JOIN cte_product_gdiv pg
    ON b.pcode = pg.pcode

-- 5. JOIN GRADE TOKO (TERKUNCI GDIV)
LEFT JOIN cte_grading_daily gst
    ON b.source_schema   = gst.source_schema
   AND b.gdiv_id         = gst.gdiv_id
   AND b.distributor_id  = gst.distributor_id
   AND b.sls_id          = gst.sls_id
   AND b.outlet_id       = gst.outlet_id
   AND b.activity_date   = gst.visit_date

-- 6. JOIN IR DISPLAY (TERKUNCI GDIV)
LEFT JOIN cte_ir_daily ir
    ON b.source_schema   = ir.source_schema
   AND b.gdiv_id         = ir.gdiv_id
   AND b.distributor_id  = ir.distributor_id
   AND b.sls_id          = ir.sls_id
   AND b.outlet_id       = ir.outlet_id
   AND b.pcode           = ir.pcode
   AND b.activity_date   = ir.visit_date

-- 7. JOIN TARGET NMRC (TERKUNCI GDIV)
LEFT JOIN cte_nmrc_daily nm
    ON b.source_schema   = nm.source_schema
   AND b.gdiv_id         = nm.gdiv_id
   AND b.distributor_id  = nm.distributor_id
   AND b.sls_id          = nm.sls_id
   AND b.activity_date   = nm.report_date