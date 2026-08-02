{{
    config(
        schema='bift',
        materialized='table',
        alias='silver_npl_by_hierarchy_dev',
        pre_hook="SET LOCAL work_mem = '256MB';",
        indexes=[
          {'columns': ['tahun', 'periode', 'distributor_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'pcode'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'channel_id'], 'type': 'btree'}
        ]
    )
}}

-- DEV/TESTING ONLY: Filtered to tahun=2026, periode IN (4,5), distributor_id='103481'
-- Do NOT use this model in production Gold pipelines.

WITH 
-- STEP 0: Deduplicated week bridge — filtered to only needed periods
week_bridge AS (
    SELECT DISTINCT
        "year"::numeric     AS tahun,
        "period"::numeric   AS periode,
        week::numeric       AS week
    FROM spx.m_cycle3
    WHERE "year"::numeric   = 2026
      AND "period"::numeric IN (4, 5)
),

-- STEP 1: Enrich each transaction row — filtered early to target distributor & periods
-- Early filter on subdist_id + period cuts the raw scan from 50M+ rows to thousands
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
    FROM (
        SELECT *
        FROM raw_ho.vfsales_det
        WHERE sts        = '905'
        --   AND subdist_id = '103481'                -- DEV filter: single distributor
    ) s
    INNER JOIN spx.m_cycle3 c
            ON s.ord_date::date = c.cdate::date
    LEFT JOIN bift.dim_product f
           ON s.pcode = f.pcode
    WHERE c."year"::numeric   = 2026               -- DEV filter: tahun
      AND c."period"::numeric IN (4, 5)            -- DEV filter: periode
)

SELECT

    -- 1. Period (from CB Cover grain)
    cs.tahun,
    cs.periode,

    -- 2. Date & Week (week always populated from week_bridge; date NULL if no transaction)
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

    -- 8. Location
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

    -- 9. Transaction Detail (NULL when no transaction this period/week)
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

-- STEP A: CB Cover — subquery filtered to single distributor, SS & target periods
FROM (
    SELECT *
    FROM bift.dim_fcustsls_staging
    WHERE tahun          = 2026                    -- DEV filter: tahun
      AND periode        IN (4, 5)                 -- DEV filter: periode
) cs
INNER JOIN (
    SELECT *
    FROM bift.dim_salesman_hierarchy
    WHERE sd_id = 'WF0221'
) sh
        ON cs.distributor_id = sh.distributor_id
       AND cs.sls_id         = sh.sls_id

-- STEP B: Explode CB Cover per week — only weeks in filtered periods
INNER JOIN week_bridge wb
        ON wb.tahun   = cs.tahun
       AND wb.periode = cs.periode

-- STEP C: Left join transactions matched at week precision
LEFT JOIN trx_with_period t
       ON t.distributor_id   = cs.distributor_id
      AND t.sls_id           = cs.sls_id
      AND t.cust_id          = cs.cust_id
      AND t.tahun            = cs.tahun
      AND t.periode          = cs.periode
      AND t.week             = wb.week
