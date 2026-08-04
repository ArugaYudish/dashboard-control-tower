{{
    config(
        schema='bift',
        materialized='table',
        alias='gold_npl_by_group_channel',
        pre_hook="SET LOCAL work_mem = '512MB';",
        indexes=[
          {'columns': ['tahun', 'periode', 'week', 'distributor_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'distributor_id'], 'type': 'btree'},
          {'columns': ['distributor_id', 'cust_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'pcode'], 'type': 'btree'},
          {'columns': ['group_channel_id'], 'type': 'btree'}
        ]
    )
}}

-- Production Gold table grouped by group_channel

WITH week_bridge AS (
    SELECT DISTINCT
        "year"::numeric     AS tahun,
        "period"::numeric   AS periode,
        week::numeric       AS week
    FROM spx.m_cycle3
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

    -- Group Channel
    s.group_channel_id,
    s.group_channel_nm,

    -- Customer / Outlet
    s.cust_id,
    s.cust_nm,

    -- Product Placeholder
    'ALL'                                                             AS pcode,
    'ALL Products'                                                    AS pcode_nm,
    'ALL'                                                             AS subbrand_id,
    'ALL Subbrands'                                                   AS subbrand_nm,

    0                                                                 AS order_count,
    0                                                                 AS qty_carton,
    0                                                                 AS inv_val

FROM {{ ref('silver_npl_by_hierarchy') }} s
INNER JOIN week_bridge wb
        ON wb.tahun   = s.tahun
       AND wb.periode = s.periode
WHERE s.is_transaction = 0
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
    s.group_channel_id,
    s.group_channel_nm,
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

    -- Group Channel
    t.group_channel_id,
    t.group_channel_nm,

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

FROM {{ ref('silver_npl_by_hierarchy') }} t
WHERE t.is_transaction = 1
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
    t.group_channel_id,
    t.group_channel_nm,
    t.cust_id,
    t.cust_nm,
    t.pcode,
    t.pcode_nm,
    t.subbrand_id,
    t.subbrand_nm
