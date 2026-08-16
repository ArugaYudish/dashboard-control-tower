{{
    config(
        schema='bift',
        materialized='table',
        alias='silver_oa_performance',
        indexes=[
          {'columns': ['tahun', 'periode', 'distributor_id'],         'type': 'btree'},
          {'columns': ['tahun', 'periode', 'sls_id'],                 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'cust_id'],                'type': 'btree'},
          {'columns': ['tahun', 'periode', 'pcode'],                  'type': 'btree'},
          {'columns': ['distributor_id', 'sls_id', 'cust_id'],        'type': 'btree'},
          {'columns': ['gdiv_id', 'source_schema'],                   'type': 'btree'},
          {'columns': ['is_transaction'],                              'type': 'btree'}
        ]
    )
}}

-- =============================================================================
-- silver_oa_performance
-- -----------------------------------------------------------------------------
-- Purpose  : Single source of truth (SSoT) for OA (Outlet Active) performance.
--            Used as the base for gold_npl, gold_grading, and future gold tables.
--
-- Grain    : Two streams UNION ALL'd together:
--   Stream A (non_purchasing_rows) — 1 row per CB Cover outlet per PERIOD.
--                                    week / date / pcode / metrics are NULL / 0.
--   Stream B (trx_rows)           — 1 row per invoice LINE per DAY.
--                                    week from vd.week_no, periode from vd.prd_no.
--
-- Joins    : CB Cover (dim_fcustsls_staging INNER JOIN dim_salesman_hierarchy)
--            LEFT JOIN vfsales_det (sts='905') — prd_no/week_no used directly
--            LEFT JOIN dim_product (product hierarchy + carton conversion)
--
-- Filters  : tahun = var('tahun', 2026)   [CB Cover + trx]
-- =============================================================================

WITH

-- ---------------------------------------------------------------------------
-- STEP 1 : CB Cover — covered outlets for a given tahun, all gdiv/schemas.
--          Enriched with full salesman hierarchy via INNER JOIN.
--          Join key: distributor_id + sls_id + source_schema.
--          Var  : tahun (default 2026).
-- ---------------------------------------------------------------------------
cb_cover AS (
    SELECT
        cs.source_schema,
        cs.tahun,
        cs.periode,
        cs.distributor_id,
        cs.sls_id,
        cs.cust_id,
        cs.cust_nm,

        -- Channel & Outlet classification
        cs.channel_id,
        cs.channel_nm,
        cs.group_channel_id,
        cs.group_channel_nm,

        -- Visit & Route
        cs.cycle_kunjungan,
        cs.route,

        -- Location
        cs.provinsi_code,   cs.provinsi_name,
        cs.kabupaten_code,  cs.kabupaten_name,
        cs.kecamatan_code,  cs.kecamatan_name,
        cs.kelurahan_code,  cs.kelurahan_name,
        cs.latitude,
        cs.longitude,

        -- Sales Hierarchy (from dim_salesman_hierarchy)
        sh.gdiv_id,
        sh.gdiv_nm,
        sh.sd_id,
        sh.sd_nm,
        sh.nsm_id,
        sh.nsm_nm,
        sh.grsm_id,
        sh.grsm_nm,
        sh.rsm_id,
        sh.rsm_nm,
        sh.ss_id,
        sh.ss_nm,
        sh.distributor_nm,
        sh.sls_nm,

        -- Salesforce (from dim_fcustsls_staging for group levels, hierarchy for base)
        cs.gsalesforce1_id,
        cs.gsalesforce1_nm,
        cs.gsalesforce2_id,
        cs.gsalesforce2_nm,
        sh.salesforce_id,
        sh.salesforce_nm,
        sh.salesforce_div_id,
        sh.salesforce_div_nm,

        -- Salesman metadata
        sh.team_id,
        sh.opr_type

    FROM bift.dim_fcustsls_staging cs
    INNER JOIN bift.dim_salesman_hierarchy sh
            ON cs.distributor_id = sh.distributor_id
           AND cs.sls_id         = sh.sls_id
           AND cs.source_schema  = sh.source_schema
    WHERE cs.tahun = {{ var('tahun', 2026) }}
      AND (
          sh.termin_year IS NULL
          OR (cs.tahun * 100 + cs.periode) <= (sh.termin_year * 100 + sh.termin_period)
      )
),

-- ---------------------------------------------------------------------------
-- STEP 2 : Transactions — spx.vfsales_det filtered to approved invoices.
--          vd.prd_no    = period number   → mapped as: periode
--          vd.week_no   = cycle week      → mapped as: week
--          tahun derived from EXTRACT(YEAR FROM ord_date) — no m_cycle3 join.
--          Product hierarchy enriched via LEFT JOIN dim_product.
-- ---------------------------------------------------------------------------
trx AS (
    SELECT
        vd.subdist_id                                    AS distributor_id,
        vd.slsno                                         AS sls_id,
        vd.custno                                        AS cust_id,
        EXTRACT(YEAR FROM vd.ord_date::date)::numeric    AS tahun,
        vd.prd_no::numeric                               AS periode, -- period from vfsalesdet
        vd.week_no::numeric                              AS week,    -- cycle week from vfsalesdet
        vd.ord_date::date                                AS date,
        vd.inv_date::date                                AS inv_date,
        vd.inv_no                                        AS inv_no,
        vd.pcode                                         AS pcode,
        COALESCE(vd.inv_qty::numeric, 0)                 AS inv_qty,
        COALESCE(vd.inv_val::numeric, 0)                 AS inv_val,

        -- Product hierarchy from dim_product
        f.pcode_nm,
        COALESCE(
            vd.inv_qty::numeric / NULLIF(f.convunit2 * f.convunit3, 0),
            0
        )                                                AS qty_carton,
        f.gdiv_id                                        AS product_gdiv_id,
        f.gdiv_nm                                        AS product_gdiv_nm,
        f.div_id,
        f.div_nm,
        f.team_id                                        AS product_team_id,
        f.team_nm                                        AS product_team_nm,
        f.class_team_id,
        f.class_team_nm,
        f.subbrand_id,
        f.subbrand_nm,
        f.cat_id,
        f.cat_nm,
        f.sbu_id,
        f.sbu_nm

    FROM (
        SELECT *
        FROM bift.mv_fsales_det
    ) as vd
    LEFT JOIN bift.dim_product f
           ON vd.pcode = f.pcode
),

-- ---------------------------------------------------------------------------
-- STEP 3A : Purchasing stream (Stream B)
--           1 row per invoice LINE per DAY for CB-covered outlets.
--           Join matches CB Cover to trx on distributor + salesman + outlet.
--           Period alignment: cb.tahun + cb.periode from dim_fcustsls_staging,
--           trx week resolved from vfsalesdet directly.
-- ---------------------------------------------------------------------------
trx_rows AS (
    SELECT
        cb.source_schema,
        cb.tahun,
        cb.periode,
        trx.week,
        trx.date,
        trx.inv_date,

        -- Sales Hierarchy
        cb.gdiv_id,         cb.gdiv_nm,
        cb.sd_id,           cb.sd_nm,
        cb.nsm_id,          cb.nsm_nm,
        cb.grsm_id,         cb.grsm_nm,
        cb.rsm_id,          cb.rsm_nm,
        cb.ss_id,           cb.ss_nm,
        cb.distributor_id,  cb.distributor_nm,
        cb.sls_id,          cb.sls_nm,

        -- Salesforce
        cb.gsalesforce1_id, cb.gsalesforce1_nm,
        cb.gsalesforce2_id, cb.gsalesforce2_nm,
        cb.salesforce_id,   cb.salesforce_nm,
        cb.salesforce_div_id, cb.salesforce_div_nm,
        cb.team_id,
        cb.opr_type,

        -- Channel & Outlet
        cb.cust_id,         cb.cust_nm,
        cb.channel_id,      cb.channel_nm,
        cb.group_channel_id, cb.group_channel_nm,
        cb.cycle_kunjungan,
        cb.route,

        -- Location
        cb.provinsi_code,   cb.provinsi_name,
        cb.kabupaten_code,  cb.kabupaten_name,
        cb.kecamatan_code,  cb.kecamatan_name,
        cb.kelurahan_code,  cb.kelurahan_name,
        cb.latitude,
        cb.longitude,

        -- Transaction
        trx.inv_no,
        trx.pcode,
        trx.pcode_nm,
        trx.inv_qty,
        trx.inv_val,
        trx.qty_carton,

        -- Product Hierarchy
        trx.product_gdiv_id AS product_gdiv_id,
        trx.product_gdiv_nm AS product_gdiv_nm,
        trx.div_id,         trx.div_nm,
        trx.product_team_id, trx.product_team_nm,
        trx.class_team_id,  trx.class_team_nm,
        trx.subbrand_id,    trx.subbrand_nm,
        trx.cat_id,         trx.cat_nm,
        trx.sbu_id,         trx.sbu_nm,

        1                   AS is_transaction

    FROM cb_cover cb
    INNER JOIN trx
            ON cb.distributor_id = trx.distributor_id
           AND cb.sls_id         = trx.sls_id
           AND cb.cust_id        = trx.cust_id
           AND cb.tahun          = trx.tahun
           AND cb.periode        = trx.periode
),

-- ---------------------------------------------------------------------------
-- STEP 3B : Master CB stream (Stream A)
--           1 row per CB Cover outlet per PERIOD (ALL outlets, including
--           those that transacted). Ensures CB Cover is always 100% complete
--           regardless of date/week filter downstream.
--           week / date / pcode / metrics set to NULL / 0 (no week explosion).
-- ---------------------------------------------------------------------------
non_purchasing_rows AS (
    SELECT
        cb.source_schema,
        cb.tahun,
        cb.periode,
        0::numeric                  AS week,      -- 0 = no transaction week (ClickHouse: no Nullable(UInt))
        NULL::date                  AS date,      -- NULL = no transaction date (Nullable(Date))
        NULL::date                  AS inv_date,  -- NULL = no invoice date    (Nullable(Date))

        -- Sales Hierarchy
        cb.gdiv_id,         cb.gdiv_nm,
        cb.sd_id,           cb.sd_nm,
        cb.nsm_id,          cb.nsm_nm,
        cb.grsm_id,         cb.grsm_nm,
        cb.rsm_id,          cb.rsm_nm,
        cb.ss_id,           cb.ss_nm,
        cb.distributor_id,  cb.distributor_nm,
        cb.sls_id,          cb.sls_nm,

        -- Salesforce
        cb.gsalesforce1_id, cb.gsalesforce1_nm,
        cb.gsalesforce2_id, cb.gsalesforce2_nm,
        cb.salesforce_id,   cb.salesforce_nm,
        cb.salesforce_div_id, cb.salesforce_div_nm,
        cb.team_id,
        cb.opr_type,

        -- Channel & Outlet
        cb.cust_id,         cb.cust_nm,
        cb.channel_id,      cb.channel_nm,
        cb.group_channel_id, cb.group_channel_nm,
        cb.cycle_kunjungan,
        cb.route,

        -- Location
        cb.provinsi_code,   cb.provinsi_name,
        cb.kabupaten_code,  cb.kabupaten_name,
        cb.kecamatan_code,  cb.kecamatan_name,
        cb.kelurahan_code,  cb.kelurahan_name,
        cb.latitude,
        cb.longitude,

        -- Transaction Placeholders ('' for strings — ClickHouse String is non-Nullable by default)
        ''                  AS inv_no,
        ''                  AS pcode,
        ''                  AS pcode_nm,
        0                   AS inv_qty,
        0                   AS inv_val,
        0                   AS qty_carton,

        -- Product Hierarchy Placeholders ('' for strings)
        ''                  AS product_gdiv_id,
        ''                  AS product_gdiv_nm,
        ''                  AS div_id,
        ''                  AS div_nm,
        ''                  AS product_team_id,
        ''                  AS product_team_nm,
        ''                  AS class_team_id,
        ''                  AS class_team_nm,
        ''                  AS subbrand_id,
        ''                  AS subbrand_nm,
        ''                  AS cat_id,
        ''                  AS cat_nm,
        ''                  AS sbu_id,
        ''                  AS sbu_nm,

        0                   AS is_transaction

    FROM cb_cover cb
)

-- ---------------------------------------------------------------------------
-- FINAL : Union both streams.
--         Downstream gold tables apply tahun / periode / gdiv filters.
-- ---------------------------------------------------------------------------
SELECT * FROM trx_rows
UNION ALL
SELECT * FROM non_purchasing_rows
