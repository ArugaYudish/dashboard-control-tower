{{
    config(
        schema='bift',
        materialized='table',
        alias='silver_npl_by_hierarchy',
        pre_hook="SET LOCAL work_mem = '512MB';",
        indexes=[
          -- Time Slicing
          {'columns': ['tahun', 'periode', 'week'], 'type': 'btree'},
          {'columns': ['date'], 'type': 'btree'},

          -- Product Filters
          {'columns': ['tahun', 'periode', 'pcode'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'subbrand_id'], 'type': 'btree'},

          -- Salesforce Filters
          {'columns': ['tahun', 'periode', 'salesforce_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'gsalesforce_id'], 'type': 'btree'},

          -- Channel Filters
          {'columns': ['tahun', 'periode', 'channel_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'group_channel_id'], 'type': 'btree'},

          -- Hierarchy & Customer Lookups
          {'columns': ['tahun', 'periode', 'distributor_id'], 'type': 'btree'},
          {'columns': ['sd_id', 'nsm_id', 'grsm_id', 'rsm_id', 'ss_id', 'distributor_id'], 'type': 'btree'},
          {'columns': ['distributor_id', 'sls_id', 'cust_id'], 'type': 'btree'},
          {'columns': ['provinsi_code', 'kabupaten_code'], 'type': 'btree'}
        ]
    )
}}

WITH 
-- STEP 0: Deduplicated week bridge (periode -> week mapping, no date fan-out)
week_bridge AS (
    SELECT DISTINCT
        "year"::numeric     AS tahun,
        "period"::numeric   AS periode,
        week::numeric       AS week
    FROM spx.m_cycle3
),

-- STEP 1: Enrich each transaction row (at inv_no + pcode grain) with tahun/periode/week
-- No grouping — every transaction line is preserved as-is
trx_with_period AS (
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
        -- Product info joined early (before CB Cover fan-out) for performance
        f.pcode_nm,
        COALESCE(
            s.inv_qty::numeric / NULLIF(f.convunit2 * f.convunit3, 0),
            0
        )                           AS qty_carton,
        f.gdiv_id,
        f.gdiv_nm,
        f.div_id,
        f.div_nm,
        f.team_id                   AS product_team_id,
        f.team_nm                   AS product_team_nm,
        f.class_team_id,
        f.class_team_nm,
        f.subbrand_id,
        f.subbrand_nm,
        f.cat_id,
        f.cat_nm,
        f.sbu_id,
        f.sbu_nm
    FROM raw_ho.vfsales_det s
    -- Bridge: map daily ord_date -> tahun/periode/week via m_cycle3
    INNER JOIN spx.m_cycle3 c
            ON s.ord_date::date = c.cdate::date
    -- Product lookup joined here (small dataset) instead of after 40G CB Cover fan-out
    LEFT JOIN bift.dim_product f
           ON s.pcode = f.pcode
    WHERE s.sts = '905'
)

SELECT

    -- 1. Period (from CB Cover grain)
    cs.tahun,
    cs.periode,

    -- 2. Date & Week (week is always populated from week_bridge; date is NULL if no transaction)
    wb.week,
    t.date,

    -- 3. Sales Hierarchy
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

    -- 4. Distributor
    sh.distributor_id,
    sh.distributor_nm,

    -- 5. Salesman & Salesforce
    sh.sls_id,
    sh.sls_nm,
    sh.salesforce_id,
    sh.salesforce_nm,
    sh.gsalesforce_id,
    sh.gsalesforce_nm,
    sh.salesforce_div_id,
    sh.salesforce_div_nm,
    sh.team_id,
    sh.opr_type,

    -- 6. Customer & Channel (from CB Cover)
    cs.cust_id,
    cs.cust_nm,
    cs.channel_id,
    cs.channel_nm,
    cs.group_channel_id,
    cs.group_channel_nm,

    -- 7. Visit Cycle (from CB Cover)
    cs.cycle_kunjungan,
    cs.route,

    -- 8. Location (from CB Cover — already enriched via dim_customer + dim_lokasi)
    cs.provinsi_code,
    cs.provinsi_name,
    cs.kabupaten_code,
    cs.kabupaten_name,
    cs.kecamatan_code,
    cs.kecamatan_name,
    cs.kelurahan_code,
    cs.kelurahan_name,
    cs.latitude,
    cs.longitude,

    -- 9. Transaction Detail (NULL when no transaction in this period/week)
    t.inv_no,
    t.pcode,
    t.pcode_nm,
    t.inv_qty,
    t.inv_val,
    t.qty_carton,

    -- 10. Product Hierarchy
    t.gdiv_id,
    t.gdiv_nm,
    t.div_id,
    t.div_nm,
    t.product_team_id,
    t.product_team_nm,
    t.class_team_id,
    t.class_team_nm,
    t.subbrand_id,
    t.subbrand_nm,
    t.cat_id,
    t.cat_nm,
    t.sbu_id,
    t.sbu_nm,

    -- 11. Transaction Flag
    CASE
        WHEN COALESCE(t.inv_val, 0) > 0 THEN 1
        ELSE 0
    END                             AS is_transaction

-- STEP A: CB Cover — outlets covered per tahun-periode
FROM bift.dim_salesman_hierarchy sh
INNER JOIN bift.dim_fcustsls_staging cs
        ON cs.distributor_id = sh.distributor_id
       AND cs.sls_id         = sh.sls_id

-- STEP B: Explode CB Cover per week in that period so every week has CB cover representation
INNER JOIN week_bridge wb
        ON wb.tahun   = cs.tahun
       AND wb.periode = cs.periode

-- STEP C: Left join transaction rows matched via distributor, sls, cust, tahun, periode, AND week
LEFT JOIN trx_with_period t
       ON t.distributor_id   = cs.distributor_id
      AND t.sls_id           = cs.sls_id
      AND t.cust_id          = cs.cust_id
      AND t.tahun            = cs.tahun
      AND t.periode          = cs.periode
      AND t.week             = wb.week

-- Product data is already resolved inside trx_with_period CTE (early join for performance)