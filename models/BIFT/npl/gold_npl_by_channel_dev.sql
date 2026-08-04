{{
    config(
        schema='bift',
        materialized='table',
        alias='gold_npl_by_channel_dev',
        pre_hook="SET LOCAL work_mem = '256MB';",
        indexes=[
          {'columns': ['tahun', 'periode', 'week', 'distributor_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'distributor_id'], 'type': 'btree'},
          {'columns': ['distributor_id', 'cust_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'pcode'], 'type': 'btree'},
          {'columns': ['channel_id'], 'type': 'btree'}
        ]
    )
}}

-- DEV/TESTING ONLY: Gold table grouped by channel

WITH week_bridge AS (
    SELECT DISTINCT
        "year"::numeric     AS tahun,
        "period"::numeric   AS periode,
        week::numeric       AS week
    FROM spx.m_cycle3
    WHERE "year"::numeric   = 2026
      AND "period"::numeric IN (4, 5)
),

silver_non_tx AS (
    SELECT *
    FROM bift.silver_npl_by_hierarchy_dev
    WHERE is_transaction = 0
),

silver_tx AS (
    SELECT *
    FROM bift.silver_npl_by_hierarchy_dev
    WHERE is_transaction = 1
)

-- STREAM A: Non-purchasing CB Outlets from Silver (1 row per outlet x week)
SELECT
    s.source_schema,
    s.tahun,
    s.periode,
    wb.week,

    -- Sales Hierarchy
    s.sd_id,
    s.sd_nm,
    s.nsm_id,
    s.nsm_nm,
    s.grsm_id,
    s.grsm_nm,
    s.rsm_id,
    s.rsm_nm,
    s.ss_id,
    s.ss_nm,

    -- Distributor
    s.distributor_id,
    s.distributor_nm,

    -- Channel
    s.channel_id,
    s.channel_nm,

    -- Customer / Outlet
    s.cust_id,
    s.cust_nm,

    -- Product Placeholder
    'N/A'                                                             AS pcode,
    'N/A'                                                    AS pcode_nm,
    'N/A'                                                             AS subbrand_id,
    'N/A'                                                   AS subbrand_nm,

    0                                                                 AS order_count,
    0                                                                 AS qty_carton,
    0                                                                 AS inv_val

FROM silver_non_tx s
INNER JOIN week_bridge wb
        ON wb.tahun   = s.tahun
       AND wb.periode = s.periode
GROUP BY
    s.source_schema,
    s.tahun,
    s.periode,
    wb.week,
    s.sd_id,
    s.sd_nm,
    s.nsm_id,
    s.nsm_nm,
    s.grsm_id,
    s.grsm_nm,
    s.rsm_id,
    s.rsm_nm,
    s.ss_id,
    s.ss_nm,
    s.distributor_id,
    s.distributor_nm,
    s.channel_id,
    s.channel_nm,
    s.cust_id,
    s.cust_nm

UNION ALL

-- STREAM B: Real Transaction Rows from Silver (Aggregated per outlet + pcode + week)
SELECT
    t.source_schema,
    t.tahun,
    t.periode,
    t.week,

    -- Sales Hierarchy
    t.sd_id,
    t.sd_nm,
    t.nsm_id,
    t.nsm_nm,
    t.grsm_id,
    t.grsm_nm,
    t.rsm_id,
    t.rsm_nm,
    t.ss_id,
    t.ss_nm,

    -- Distributor
    t.distributor_id,
    t.distributor_nm,

    -- Channel
    t.channel_id,
    t.channel_nm,

    -- Customer / Outlet
    t.cust_id,
    t.cust_nm,

    -- Product
    t.pcode,
    t.pcode_nm,
    t.subbrand_id,
    t.subbrand_nm,

    COUNT(DISTINCT t.inv_no)                                          AS order_count,
    SUM(COALESCE(t.qty_carton, 0))                                    AS qty_carton,
    SUM(COALESCE(t.inv_val, 0))                                       AS inv_val

FROM silver_tx t

GROUP BY
    t.source_schema,
    t.tahun,
    t.periode,
    t.week,
    t.sd_id,
    t.sd_nm,
    t.nsm_id,
    t.nsm_nm,
    t.grsm_id,
    t.grsm_nm,
    t.rsm_id,
    t.rsm_nm,
    t.ss_id,
    t.ss_nm,
    t.distributor_id,
    t.distributor_nm,
    t.channel_id,
    t.channel_nm,
    t.cust_id,
    t.cust_nm,
    t.pcode,
    t.pcode_nm,
    t.subbrand_id,
    t.subbrand_nm
