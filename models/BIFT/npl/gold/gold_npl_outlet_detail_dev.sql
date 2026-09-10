{{
    config(
        schema='bift',
        materialized='table',
        alias='gold_npl_outlet_detail_dev',
        pre_hook=["set local work_mem = '1GB'"],
        indexes=[
          {'columns': ['tahun', 'periode', 'week', 'distributor_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'distributor_id'],         'type': 'btree'},
          {'columns': ['distributor_id', 'cust_id'],                  'type': 'btree'},
          {'columns': ['tahun', 'periode', 'pcode'],                  'type': 'btree'},
          {'columns': ['is_transaction'],                              'type': 'btree'},
          {'columns': ['sls_id'],                                      'type': 'btree'},
          {'columns': ['classification_id'],                           'type': 'btree'},
          {'columns': ['gdiv_id'],                                     'type': 'btree'},
          {'columns': ['date'],                                        'type': 'btree'}
        ]
    )
}}

-- DEV/TESTING ONLY: Direct Gold Outlet Detail Model (tahun = 2026)
-- Built from Silver OA Performance (silver_oa_performance).
-- Pre-formats all _nm columns as "ID - Name" (or '' if ID is null/empty).
-- Stream A (non_purchasing): Master CB — 1 row per ALL CB outlets per period (week = NULL, date = NULL).
-- Stream B (purchasing): 1 row per outlet per product per transaction date (date = s.inv_date, week = s.week).
--
-- Optimization vs original:
--   1. GROUP BY reduced from ~33 cols to ~18 cols — _nm removed, replaced with MAX(_nm).
--      _nm is functionally dependent on _id, so MAX picks the correct (only) value per group.
--   2. Formatting (CASE WHEN NULLIF) moved to wrapper CTEs, not inside GROUP BY.
--   3. Shared cc_lookup CTE pre-computes classification join once for both streams.
--   4. work_mem = 1GB to avoid disk spill during sort.

-- ============================================================
-- Shared: pre-compute classification lookup (tiny: ~780 rows)
-- ============================================================
WITH cc_lookup AS (
    SELECT
        cc.channel_id,
        cc.classification_id,
        dc.classification_nm
    FROM raw_ficom_m2.m_channel_classifications cc
    LEFT JOIN bift.dim_classifications dc
           ON cc.classification_id = dc.classification_id
),

-- ============================================================
-- Stream A RAW: GROUP BY ID columns only (not _nm)
-- ~18 cols in GROUP BY vs original ~33 cols
-- ============================================================
non_purchasing_raw AS (
    SELECT
        COALESCE(s.source_schema, '')     AS source_schema,
        s.tahun,
        s.periode,
        -- IDs in GROUP BY
        COALESCE(s.gdiv_id, '')           AS gdiv_id,
        COALESCE(s.sd_id, '')             AS sd_id,
        COALESCE(s.nsm_id, '')            AS nsm_id,
        COALESCE(s.grsm_id, '')           AS grsm_id,
        COALESCE(s.rsm_id, '')            AS rsm_id,
        COALESCE(s.ss_id, '')             AS ss_id,
        COALESCE(s.distributor_id, '')    AS distributor_id,
        COALESCE(s.gsalesforce1_id, '')   AS gsalesforce1_id,
        COALESCE(s.gsalesforce2_id, '')   AS gsalesforce2_id,
        COALESCE(s.salesforce_id, '')     AS salesforce_id,
        COALESCE(s.sls_id, '')            AS sls_id,
        COALESCE(s.group_channel_id, '')  AS group_channel_id,
        COALESCE(s.channel_id, '')        AS channel_id,
        COALESCE(cc.classification_id, '') AS classification_id,
        COALESCE(s.cust_id, '')           AS cust_id,
        -- _nm via MAX (functionally dependent on _id, same value per group)
        MAX(s.gdiv_nm)            AS gdiv_nm,
        MAX(s.sd_nm)              AS sd_nm,
        MAX(s.nsm_nm)             AS nsm_nm,
        MAX(s.grsm_nm)            AS grsm_nm,
        MAX(s.rsm_nm)             AS rsm_nm,
        MAX(s.ss_nm)              AS ss_nm,
        MAX(s.distributor_nm)     AS distributor_nm,
        MAX(s.gsalesforce1_nm)    AS gsalesforce1_nm,
        MAX(s.gsalesforce2_nm)    AS gsalesforce2_nm,
        MAX(s.salesforce_nm)      AS salesforce_nm,
        MAX(s.sls_nm)             AS sls_nm,
        MAX(s.group_channel_nm)   AS group_channel_nm,
        MAX(s.channel_nm)         AS channel_nm,
        MAX(cc.classification_nm) AS classification_nm,
        MAX(s.cust_nm)            AS cust_nm
    FROM bift.bronze_cb s
    LEFT JOIN cc_lookup cc
           ON s.channel_id    = cc.channel_id
          AND s.source_schema = 'm2'
    WHERE s.tahun   = {{ var('tahun', 2026) }}
      AND s.periode = {{ var('periode', 1) }}
    GROUP BY
        COALESCE(s.source_schema, ''), s.tahun, s.periode,
        COALESCE(s.gdiv_id, ''),
        COALESCE(s.sd_id, ''),
        COALESCE(s.nsm_id, ''),
        COALESCE(s.grsm_id, ''),
        COALESCE(s.rsm_id, ''),
        COALESCE(s.ss_id, ''),
        COALESCE(s.distributor_id, ''),
        COALESCE(s.gsalesforce1_id, ''),
        COALESCE(s.gsalesforce2_id, ''),
        COALESCE(s.salesforce_id, ''),
        COALESCE(s.sls_id, ''),
        COALESCE(s.group_channel_id, ''),
        COALESCE(s.channel_id, ''),
        COALESCE(cc.classification_id, ''),
        COALESCE(s.cust_id, '')
),

-- ============================================================
-- Stream A FORMATTED: apply "ID - Name" formatting post-GROUP BY
-- ============================================================
non_purchasing AS (
    SELECT
        source_schema,
        COALESCE(tahun, 0)    AS tahun,
        COALESCE(periode, 0)  AS periode,
        NULL::numeric         AS week,
        NULL::date            AS date,

        gdiv_id,
        CASE WHEN NULLIF(gdiv_id, '') IS NOT NULL
             THEN gdiv_id || ' - ' || COALESCE(gdiv_nm, '') ELSE '' END         AS gdiv_nm,

        sd_id,
        CASE WHEN NULLIF(sd_id, '') IS NOT NULL
             THEN sd_id || ' - ' || COALESCE(sd_nm, '') ELSE '' END             AS sd_nm,

        nsm_id,
        CASE WHEN NULLIF(nsm_id, '') IS NOT NULL
             THEN nsm_id || ' - ' || COALESCE(nsm_nm, '') ELSE '' END           AS nsm_nm,

        grsm_id,
        CASE WHEN NULLIF(grsm_id, '') IS NOT NULL
             THEN grsm_id || ' - ' || COALESCE(grsm_nm, '') ELSE '' END         AS grsm_nm,

        rsm_id,
        CASE WHEN NULLIF(rsm_id, '') IS NOT NULL
             THEN rsm_id || ' - ' || COALESCE(rsm_nm, '') ELSE '' END           AS rsm_nm,

        ss_id,
        CASE WHEN NULLIF(ss_id, '') IS NOT NULL
             THEN ss_id || ' - ' || COALESCE(ss_nm, '') ELSE '' END             AS ss_nm,

        distributor_id,
        CASE WHEN NULLIF(distributor_id, '') IS NOT NULL
             THEN distributor_id || ' - ' || COALESCE(distributor_nm, '') ELSE '' END AS distributor_nm,

        gsalesforce1_id,
        CASE WHEN NULLIF(gsalesforce1_id, '') IS NOT NULL
             THEN gsalesforce1_id || ' - ' || COALESCE(gsalesforce1_nm, '') ELSE '' END AS gsalesforce1_nm,

        gsalesforce2_id,
        CASE WHEN NULLIF(gsalesforce2_id, '') IS NOT NULL
             THEN gsalesforce2_id || ' - ' || COALESCE(gsalesforce2_nm, '') ELSE '' END AS gsalesforce2_nm,

        salesforce_id,
        CASE WHEN NULLIF(salesforce_id, '') IS NOT NULL
             THEN salesforce_id || ' - ' || COALESCE(salesforce_nm, '') ELSE '' END AS salesforce_nm,

        sls_id,
        CASE WHEN NULLIF(sls_id, '') IS NOT NULL
             THEN sls_id || ' - ' || COALESCE(sls_nm, '') ELSE '' END           AS sls_nm,

        group_channel_id,
        CASE WHEN NULLIF(group_channel_id, '') IS NOT NULL
             THEN group_channel_id || ' - ' || COALESCE(group_channel_nm, '') ELSE '' END AS group_channel_nm,

        channel_id,
        CASE WHEN NULLIF(channel_id, '') IS NOT NULL
             THEN channel_id || ' - ' || COALESCE(channel_nm, '') ELSE '' END   AS channel_nm,

        classification_id,
        CASE WHEN NULLIF(classification_id, '') IS NOT NULL
             THEN classification_id || ' - ' || COALESCE(classification_nm, '') ELSE '' END AS classification_nm,

        cust_id,
        CASE WHEN NULLIF(cust_id, '') IS NOT NULL
             THEN cust_id || ' - ' || COALESCE(cust_nm, '') ELSE '' END         AS cust_nm,

        'N/A'       AS pcode,
        'N/A'       AS pcode_nm,
        'N/A'       AS subbrand_id,
        'N/A'       AS subbrand_nm,
        0           AS order_count,
        0::numeric  AS qty_carton,
        0::numeric  AS inv_val,
        0           AS is_transaction
    FROM non_purchasing_raw
),

-- ============================================================
-- Stream B RAW: GROUP BY ID columns only (not _nm)
-- ~20 cols in GROUP BY vs original ~37 cols
-- ============================================================
purchasing_raw AS (
    SELECT
        COALESCE(s.source_schema, '')     AS source_schema,
        s.tahun,
        s.periode,
        s.week,
        s.inv_date,
        -- IDs in GROUP BY
        COALESCE(s.gdiv_id, '')           AS gdiv_id,
        COALESCE(s.sd_id, '')             AS sd_id,
        COALESCE(s.nsm_id, '')            AS nsm_id,
        COALESCE(s.grsm_id, '')           AS grsm_id,
        COALESCE(s.rsm_id, '')            AS rsm_id,
        COALESCE(s.ss_id, '')             AS ss_id,
        COALESCE(s.distributor_id, '')    AS distributor_id,
        COALESCE(s.gsalesforce1_id, '')   AS gsalesforce1_id,
        COALESCE(s.gsalesforce2_id, '')   AS gsalesforce2_id,
        COALESCE(s.salesforce_id, '')     AS salesforce_id,
        COALESCE(s.sls_id, '')            AS sls_id,
        COALESCE(s.group_channel_id, '')  AS group_channel_id,
        COALESCE(s.channel_id, '')        AS channel_id,
        COALESCE(cc.classification_id, '') AS classification_id,
        COALESCE(s.cust_id, '')           AS cust_id,
        COALESCE(s.pcode, '')             AS pcode,
        COALESCE(s.subbrand_id, '')       AS subbrand_id,
        -- _nm via MAX
        MAX(s.gdiv_nm)            AS gdiv_nm,
        MAX(s.sd_nm)              AS sd_nm,
        MAX(s.nsm_nm)             AS nsm_nm,
        MAX(s.grsm_nm)            AS grsm_nm,
        MAX(s.rsm_nm)             AS rsm_nm,
        MAX(s.ss_nm)              AS ss_nm,
        MAX(s.distributor_nm)     AS distributor_nm,
        MAX(s.gsalesforce1_nm)    AS gsalesforce1_nm,
        MAX(s.gsalesforce2_nm)    AS gsalesforce2_nm,
        MAX(s.salesforce_nm)      AS salesforce_nm,
        MAX(s.sls_nm)             AS sls_nm,
        MAX(s.group_channel_nm)   AS group_channel_nm,
        MAX(s.channel_nm)         AS channel_nm,
        MAX(cc.classification_nm) AS classification_nm,
        MAX(s.cust_nm)            AS cust_nm,
        MAX(s.pcode_nm)           AS pcode_nm,
        MAX(s.subbrand_nm)        AS subbrand_nm,
        -- Aggregates
        COUNT(DISTINCT s.inv_no)        AS order_count,
        COALESCE(SUM(s.qty_carton), 0)  AS qty_carton,
        COALESCE(SUM(s.inv_val), 0)     AS inv_val
    FROM bift.silver_oa_transaction s
    LEFT JOIN cc_lookup cc
           ON s.channel_id    = cc.channel_id
          AND s.source_schema = 'm2'
    GROUP BY
        COALESCE(s.source_schema, ''), s.tahun, s.periode, s.week, s.inv_date,
        COALESCE(s.gdiv_id, ''),
        COALESCE(s.sd_id, ''),
        COALESCE(s.nsm_id, ''),
        COALESCE(s.grsm_id, ''),
        COALESCE(s.rsm_id, ''),
        COALESCE(s.ss_id, ''),
        COALESCE(s.distributor_id, ''),
        COALESCE(s.gsalesforce1_id, ''),
        COALESCE(s.gsalesforce2_id, ''),
        COALESCE(s.salesforce_id, ''),
        COALESCE(s.sls_id, ''),
        COALESCE(s.group_channel_id, ''),
        COALESCE(s.channel_id, ''),
        COALESCE(cc.classification_id, ''),
        COALESCE(s.cust_id, ''),
        COALESCE(s.pcode, ''),
        COALESCE(s.subbrand_id, '')
),

-- ============================================================
-- Stream B FORMATTED: apply "ID - Name" formatting post-GROUP BY
-- ============================================================
purchasing AS (
    SELECT
        source_schema,
        COALESCE(tahun, 0)    AS tahun,
        COALESCE(periode, 0)  AS periode,
        COALESCE(week, 0)     AS week,
        inv_date              AS date,

        gdiv_id,
        CASE WHEN NULLIF(gdiv_id, '') IS NOT NULL
             THEN gdiv_id || ' - ' || COALESCE(gdiv_nm, '') ELSE '' END         AS gdiv_nm,

        sd_id,
        CASE WHEN NULLIF(sd_id, '') IS NOT NULL
             THEN sd_id || ' - ' || COALESCE(sd_nm, '') ELSE '' END             AS sd_nm,

        nsm_id,
        CASE WHEN NULLIF(nsm_id, '') IS NOT NULL
             THEN nsm_id || ' - ' || COALESCE(nsm_nm, '') ELSE '' END           AS nsm_nm,

        grsm_id,
        CASE WHEN NULLIF(grsm_id, '') IS NOT NULL
             THEN grsm_id || ' - ' || COALESCE(grsm_nm, '') ELSE '' END         AS grsm_nm,

        rsm_id,
        CASE WHEN NULLIF(rsm_id, '') IS NOT NULL
             THEN rsm_id || ' - ' || COALESCE(rsm_nm, '') ELSE '' END           AS rsm_nm,

        ss_id,
        CASE WHEN NULLIF(ss_id, '') IS NOT NULL
             THEN ss_id || ' - ' || COALESCE(ss_nm, '') ELSE '' END             AS ss_nm,

        distributor_id,
        CASE WHEN NULLIF(distributor_id, '') IS NOT NULL
             THEN distributor_id || ' - ' || COALESCE(distributor_nm, '') ELSE '' END AS distributor_nm,

        gsalesforce1_id,
        CASE WHEN NULLIF(gsalesforce1_id, '') IS NOT NULL
             THEN gsalesforce1_id || ' - ' || COALESCE(gsalesforce1_nm, '') ELSE '' END AS gsalesforce1_nm,

        gsalesforce2_id,
        CASE WHEN NULLIF(gsalesforce2_id, '') IS NOT NULL
             THEN gsalesforce2_id || ' - ' || COALESCE(gsalesforce2_nm, '') ELSE '' END AS gsalesforce2_nm,

        salesforce_id,
        CASE WHEN NULLIF(salesforce_id, '') IS NOT NULL
             THEN salesforce_id || ' - ' || COALESCE(salesforce_nm, '') ELSE '' END AS salesforce_nm,

        sls_id,
        CASE WHEN NULLIF(sls_id, '') IS NOT NULL
             THEN sls_id || ' - ' || COALESCE(sls_nm, '') ELSE '' END           AS sls_nm,

        group_channel_id,
        CASE WHEN NULLIF(group_channel_id, '') IS NOT NULL
             THEN group_channel_id || ' - ' || COALESCE(group_channel_nm, '') ELSE '' END AS group_channel_nm,

        channel_id,
        CASE WHEN NULLIF(channel_id, '') IS NOT NULL
             THEN channel_id || ' - ' || COALESCE(channel_nm, '') ELSE '' END   AS channel_nm,

        classification_id,
        CASE WHEN NULLIF(classification_id, '') IS NOT NULL
             THEN classification_id || ' - ' || COALESCE(classification_nm, '') ELSE '' END AS classification_nm,

        cust_id,
        CASE WHEN NULLIF(cust_id, '') IS NOT NULL
             THEN cust_id || ' - ' || COALESCE(cust_nm, '') ELSE '' END         AS cust_nm,

        pcode,
        CASE WHEN NULLIF(pcode, '') IS NOT NULL
             THEN pcode || ' - ' || COALESCE(pcode_nm, '') ELSE '' END          AS pcode_nm,

        subbrand_id,
        CASE WHEN NULLIF(subbrand_id, '') IS NOT NULL
             THEN subbrand_id || ' - ' || COALESCE(subbrand_nm, '') ELSE '' END AS subbrand_nm,

        order_count,
        qty_carton,
        inv_val,
        1 AS is_transaction
    FROM purchasing_raw
)

SELECT
    concat_ws('_',
        COALESCE(is_transaction::text, '0'),
        COALESCE(source_schema, ''),
        COALESCE(tahun::text, '0'),
        COALESCE(periode::text, '0'),
        COALESCE(week::text, '0'),
        COALESCE(date::text, '1970-01-01'),
        COALESCE(distributor_id, ''),
        COALESCE(ss_id, ''),
        COALESCE(cust_id, ''),
        COALESCE(sls_id, ''),
        COALESCE(pcode, 'N/A')
    ) AS row_id,
    CURRENT_TIMESTAMP AS updated_at,
    combined.*
FROM (
    SELECT * FROM non_purchasing
    UNION ALL
    SELECT * FROM purchasing
) combined
