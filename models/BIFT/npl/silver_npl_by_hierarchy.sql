{{
    config(
        schema='bift',
        materialized='table',
        alias='silver_npl_by_hierarchy',
        pre_hook="SET LOCAL work_mem = '512MB';",
        indexes=[
          {'columns': ['tahun', 'periode', 'distributor_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'pcode'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'channel_id'], 'type': 'btree'}
        ]
    )
}}

-- Optimized Silver Fact Model (No 5-week dummy explosion bloat!)

WITH 
-- STEP 1: All valid CB Cover outlets for the period (1 row per cust_id per period)
cb_cover AS (
    SELECT
        cs.source_schema,
        cs.tahun,
        cs.periode,
        cs.distributor_id,
        cs.sls_id,
        cs.cust_id,
        cs.cust_nm,
        cs.channel_id,
        cs.channel_nm,
        cs.group_channel_id,
        cs.group_channel_nm,
        cs.cycle_kunjungan,
        cs.route,
        cs.provinsi_code, cs.provinsi_name,
        cs.kabupaten_code, cs.kabupaten_name,
        cs.kecamatan_code, cs.kecamatan_name,
        cs.kelurahan_code, cs.kelurahan_name,
        cs.latitude, cs.longitude,
        sh.sd_id, sh.sd_nm, sh.nsm_id, sh.nsm_nm,
        sh.grsm_id, sh.grsm_nm, sh.rsm_id, sh.rsm_nm,
        sh.ss_id, sh.ss_nm, sh.distributor_nm,
        sh.sls_nm, sh.salesforce_id, sh.salesforce_nm,
        cs.gsalesforce1_id, cs.gsalesforce1_nm,
        cs.gsalesforce2_id, cs.gsalesforce2_nm,
        sh.salesforce_div_id, sh.salesforce_div_nm,
        sh.team_id, sh.opr_type
    FROM bift.dim_fcustsls_staging cs
    INNER JOIN bift.dim_salesman_hierarchy sh
            ON cs.distributor_id = sh.distributor_id
           AND cs.sls_id         = sh.sls_id
),

-- STEP 2: Enriched transaction rows (resolved date & week from spx.m_cycle3)
trx AS (
    SELECT
        s.subdist_id                AS distributor_id,
        s.slsno                     AS sls_id,
        s.custno                    AS cust_id,
        c."year"::numeric           AS tahun,
        c."period"::numeric         AS periode,
        c.week::numeric             AS week,
        s.ord_date::date            AS date,
        s.inv_no,
        s.pcode,
        s.inv_qty,
        s.inv_val,
        f.pcode_nm,
        COALESCE(
            s.inv_qty::numeric / NULLIF(f.convunit2 * f.convunit3, 0),
            0
        )                           AS qty_carton,
        f.gdiv_id, f.gdiv_nm, f.div_id, f.div_nm,
        f.team_id                   AS product_team_id,
        f.team_nm                   AS product_team_nm,
        f.class_team_id, f.class_team_nm,
        f.subbrand_id, f.subbrand_nm,
        f.cat_id, f.cat_nm, f.sbu_id, f.sbu_nm
    FROM raw_ho.vfsales_det s
    INNER JOIN spx.m_cycle3 c
            ON s.ord_date::date = c.cdate::date
    LEFT JOIN bift.dim_product f
           ON s.pcode = f.pcode
    WHERE s.sts = '905'
),

-- STEP 3A: Output ALL real transaction rows (with exact week & transaction detail)
trx_rows AS (
    SELECT
        cb.source_schema,
        cb.tahun,
        cb.periode,
        trx.week,
        trx.date,

        -- Sales Hierarchy
        cb.sd_id, cb.sd_nm, cb.nsm_id, cb.nsm_nm, cb.grsm_id, cb.grsm_nm, cb.rsm_id, cb.rsm_nm, cb.ss_id, cb.ss_nm,
        cb.distributor_id, cb.distributor_nm,
        cb.sls_id, cb.sls_nm, cb.salesforce_id, cb.salesforce_nm,
        cb.gsalesforce1_id, cb.gsalesforce1_nm,
        cb.gsalesforce2_id, cb.gsalesforce2_nm,
        cb.salesforce_div_id, cb.salesforce_div_nm, cb.team_id, cb.opr_type,

        -- Customer & Channel
        cb.cust_id, cb.cust_nm, cb.channel_id, cb.channel_nm, cb.group_channel_id, cb.group_channel_nm,
        cb.cycle_kunjungan, cb.route,
        cb.provinsi_code, cb.provinsi_name, cb.kabupaten_code, cb.kabupaten_name,
        cb.kecamatan_code, cb.kecamatan_name, cb.kelurahan_code, cb.kelurahan_name,
        cb.latitude, cb.longitude,

        -- Transaction Details
        trx.inv_no, trx.pcode, trx.pcode_nm, trx.inv_qty, trx.inv_val, trx.qty_carton,
        trx.gdiv_id, trx.gdiv_nm, trx.div_id, trx.div_nm,
        trx.product_team_id, trx.product_team_nm, trx.class_team_id, trx.class_team_nm,
        trx.subbrand_id, trx.subbrand_nm, trx.cat_id, trx.cat_nm, trx.sbu_id, trx.sbu_nm,

        1 AS is_transaction
    FROM cb_cover cb
    INNER JOIN trx
            ON cb.distributor_id = trx.distributor_id
           AND cb.sls_id         = trx.sls_id
           AND cb.cust_id        = trx.cust_id
           AND cb.tahun          = trx.tahun
           AND cb.periode        = trx.periode
),

-- STEP 3B: Output 1 row per NON-PURCHASING outlet per period (No 5-week dummy duplication!)
non_purchasing_rows AS (
    SELECT
        cb.source_schema,
        cb.tahun,
        cb.periode,
        NULL::numeric               AS week,
        NULL::date                  AS date,

        -- Sales Hierarchy
        cb.sd_id, cb.sd_nm, cb.nsm_id, cb.nsm_nm, cb.grsm_id, cb.grsm_nm, cb.rsm_id, cb.rsm_nm, cb.ss_id, cb.ss_nm,
        cb.distributor_id, cb.distributor_nm,
        cb.sls_id, cb.sls_nm, cb.salesforce_id, cb.salesforce_nm,
        cb.gsalesforce1_id, cb.gsalesforce1_nm,
        cb.gsalesforce2_id, cb.gsalesforce2_nm,
        cb.salesforce_div_id, cb.salesforce_div_nm, cb.team_id, cb.opr_type,

        -- Customer & Channel
        cb.cust_id, cb.cust_nm, cb.channel_id, cb.channel_nm, cb.group_channel_id, cb.group_channel_nm,
        cb.cycle_kunjungan, cb.route,
        cb.provinsi_code, cb.provinsi_name, cb.kabupaten_code, cb.kabupaten_name,
        cb.kecamatan_code, cb.kecamatan_name, cb.kelurahan_code, cb.kelurahan_name,
        cb.latitude, cb.longitude,

        -- Transaction Placeholders
        NULL                        AS inv_no,
        NULL                        AS pcode,
        NULL                        AS pcode_nm,
        0                           AS inv_qty,
        0                           AS inv_val,
        0                           AS qty_carton,

        -- Product Hierarchy Placeholders
        NULL                        AS gdiv_id, NULL AS gdiv_nm, NULL AS div_id, NULL AS div_nm,
        NULL                        AS product_team_id, NULL AS product_team_nm,
        NULL                        AS class_team_id, NULL AS class_team_nm,
        NULL                        AS subbrand_id, NULL AS subbrand_nm,
        NULL                        AS cat_id, NULL AS cat_nm,
        NULL                        AS sbu_id, NULL AS sbu_nm,

        0 AS is_transaction
    FROM cb_cover cb
    WHERE NOT EXISTS (
        SELECT 1
        FROM trx
        WHERE trx.distributor_id = cb.distributor_id
          AND trx.sls_id         = cb.sls_id
          AND trx.cust_id        = cb.cust_id
          AND trx.tahun          = cb.tahun
          AND trx.periode        = cb.periode
    )
)

SELECT * FROM trx_rows
UNION ALL
SELECT * FROM non_purchasing_rows