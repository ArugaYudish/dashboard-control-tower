{{
    config(
        schema='bift',
        materialized='table',
        alias='gold_npl_outlet_detail_dev',
        pre_hook="SET LOCAL work_mem = '256MB';",
        indexes=[
          {'columns': ['tahun', 'periode', 'week', 'distributor_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'distributor_id'], 'type': 'btree'},
          {'columns': ['distributor_id', 'cust_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'pcode'], 'type': 'btree'},
          {'columns': ['is_transaction'], 'type': 'btree'},
          {'columns': ['sls_id'], 'type': 'btree'},
          {'columns': ['classification_id'], 'type': 'btree'}
        ]
    )
}}

-- DEV/TESTING ONLY: Outlet-level NPL detail gold table.
-- One row per: outlet (cust_id) × pcode × week.
-- Contains ALL dimension columns (hierarchy, salesforce, channel, salesman, classification)
-- so a single Metabase question can filter by any combination.
-- is_transaction = 0 → non-purchasing outlet (CB cover only)
-- is_transaction = 1 → purchasing outlet (real transaction row)

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

-- STREAM A: Non-purchasing CB Outlets (1 row per outlet × week)
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

    -- Salesforce hierarchy
    s.gsalesforce1_id,
    s.gsalesforce1_nm,
    s.gsalesforce2_id,
    s.gsalesforce2_nm,
    s.salesforce_id,
    s.salesforce_nm,

    -- Salesman
    s.sls_id,
    s.sls_nm,

    -- Channel
    s.group_channel_id,
    s.group_channel_nm,
    s.channel_id,
    s.channel_nm,

    -- Classification (M2 only; NULL for M1 & M3)
    cc.classification_id,
    dc.classification_nm,

    -- Customer / Outlet
    s.cust_id,
    s.cust_nm,

    -- Product Placeholder (no transaction)
    'N/A'                                                             AS pcode,
    'N/A'                                                             AS pcode_nm,
    'N/A'                                                             AS subbrand_id,
    'N/A'                                                             AS subbrand_nm,

    0                                                                 AS order_count,
    0                                                                 AS qty_carton,
    0                                                                 AS inv_val,

    0                                                                 AS is_transaction

FROM silver_non_tx s
INNER JOIN week_bridge wb
        ON wb.tahun   = s.tahun
       AND wb.periode = s.periode
LEFT JOIN raw_ficom_m2.m_channel_classifications cc
       ON s.channel_id    = cc.channel_id
      AND s.source_schema = 'm2'
LEFT JOIN bift.dim_classifications dc
       ON cc.classification_id = dc.classification_id
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
    s.gsalesforce1_id,
    s.gsalesforce1_nm,
    s.gsalesforce2_id,
    s.gsalesforce2_nm,
    s.salesforce_id,
    s.salesforce_nm,
    s.sls_id,
    s.sls_nm,
    s.group_channel_id,
    s.group_channel_nm,
    s.channel_id,
    s.channel_nm,
    cc.classification_id,
    dc.classification_nm,
    s.cust_id,
    s.cust_nm

UNION ALL

-- STREAM B: Real transaction rows (1 row per outlet × pcode × week)
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

    -- Salesforce hierarchy
    t.gsalesforce1_id,
    t.gsalesforce1_nm,
    t.gsalesforce2_id,
    t.gsalesforce2_nm,
    t.salesforce_id,
    t.salesforce_nm,

    -- Salesman
    t.sls_id,
    t.sls_nm,

    -- Channel
    t.group_channel_id,
    t.group_channel_nm,
    t.channel_id,
    t.channel_nm,

    -- Classification (M2 only; NULL for M1 & M3)
    cc.classification_id,
    dc.classification_nm,

    -- Customer / Outlet
    t.cust_id,
    t.cust_nm,

    -- Product (real data)
    t.pcode,
    t.pcode_nm,
    t.subbrand_id,
    t.subbrand_nm,

    COUNT(DISTINCT t.inv_no)                                          AS order_count,
    SUM(COALESCE(t.qty_carton, 0))                                    AS qty_carton,
    SUM(COALESCE(t.inv_val, 0))                                       AS inv_val,

    1                                                                 AS is_transaction

FROM silver_tx t
LEFT JOIN raw_ficom_m2.m_channel_classifications cc
       ON t.channel_id    = cc.channel_id
      AND t.source_schema = 'm2'
LEFT JOIN bift.dim_classifications dc
       ON cc.classification_id = dc.classification_id
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
    t.gsalesforce1_id,
    t.gsalesforce1_nm,
    t.gsalesforce2_id,
    t.gsalesforce2_nm,
    t.salesforce_id,
    t.salesforce_nm,
    t.sls_id,
    t.sls_nm,
    t.group_channel_id,
    t.group_channel_nm,
    t.channel_id,
    t.channel_nm,
    cc.classification_id,
    dc.classification_nm,
    t.cust_id,
    t.cust_nm,
    t.pcode,
    t.pcode_nm,
    t.subbrand_id,
    t.subbrand_nm
