{{
    config(
        schema='bift',
        materialized='table',
        alias='gold_npl_outlet_detail_dev',
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

-- DEV/TESTING ONLY: Direct Gold Outlet Detail Model (tahun = 2026, periode IN (4, 5))
-- Built directly from Raw Sources (bypassing Silver).
-- Pre-formats all _nm columns as "ID - Name" (or '' if ID is null/empty).
-- Guaranteed 100% NULL-FREE across all columns.

WITH week_bridge AS (
    SELECT DISTINCT
        COALESCE("year"::numeric, 0)     AS tahun,
        COALESCE("period"::numeric, 0)   AS periode,
        COALESCE(week::numeric, 0)       AS week
    FROM spx.m_cycle3
    WHERE "year"::numeric   = 2026
      AND "period"::numeric IN (4, 5)
),

-- Covered outlets enriched with salesman hierarchy (DEV filtered to 2026 P4-P5)
cb_cover AS (
    SELECT
        COALESCE(cs.source_schema, '')                                                  AS source_schema,
        COALESCE(cs.tahun, 0)                                                           AS tahun,
        COALESCE(cs.periode, 0)                                                         AS periode,

        -- Sales Hierarchy
        COALESCE(sh.sd_id, '')                                                          AS sd_id,
        CASE WHEN NULLIF(sh.sd_id, '') IS NOT NULL 
             THEN sh.sd_id || ' - ' || COALESCE(sh.sd_nm, '') ELSE '' END               AS sd_nm,

        COALESCE(sh.nsm_id, '')                                                         AS nsm_id,
        CASE WHEN NULLIF(sh.nsm_id, '') IS NOT NULL 
             THEN sh.nsm_id || ' - ' || COALESCE(sh.nsm_nm, '') ELSE '' END             AS nsm_nm,

        COALESCE(sh.grsm_id, '')                                                        AS grsm_id,
        CASE WHEN NULLIF(sh.grsm_id, '') IS NOT NULL 
             THEN sh.grsm_id || ' - ' || COALESCE(sh.grsm_nm, '') ELSE '' END           AS grsm_nm,

        COALESCE(sh.rsm_id, '')                                                         AS rsm_id,
        CASE WHEN NULLIF(sh.rsm_id, '') IS NOT NULL 
             THEN sh.rsm_id || ' - ' || COALESCE(sh.rsm_nm, '') ELSE '' END             AS rsm_nm,

        COALESCE(sh.ss_id, '')                                                          AS ss_id,
        CASE WHEN NULLIF(sh.ss_id, '') IS NOT NULL 
             THEN sh.ss_id || ' - ' || COALESCE(sh.ss_nm, '') ELSE '' END               AS ss_nm,

        COALESCE(cs.distributor_id, '')                                                 AS distributor_id,
        CASE WHEN NULLIF(cs.distributor_id, '') IS NOT NULL 
             THEN cs.distributor_id || ' - ' || COALESCE(sh.distributor_nm, '') ELSE '' END AS distributor_nm,

        -- Salesforce
        COALESCE(cs.gsalesforce1_id, '')                                                AS gsalesforce1_id,
        CASE WHEN NULLIF(cs.gsalesforce1_id, '') IS NOT NULL 
             THEN cs.gsalesforce1_id || ' - ' || COALESCE(cs.gsalesforce1_nm, '') ELSE '' END AS gsalesforce1_nm,

        COALESCE(cs.gsalesforce2_id, '')                                                AS gsalesforce2_id,
        CASE WHEN NULLIF(cs.gsalesforce2_id, '') IS NOT NULL 
             THEN cs.gsalesforce2_id || ' - ' || COALESCE(cs.gsalesforce2_nm, '') ELSE '' END AS gsalesforce2_nm,

        COALESCE(sh.salesforce_id, '')                                                  AS salesforce_id,
        CASE WHEN NULLIF(sh.salesforce_id, '') IS NOT NULL 
             THEN sh.salesforce_id || ' - ' || COALESCE(sh.salesforce_nm, '') ELSE '' END AS salesforce_nm,

        -- Salesman, Channel & Outlet
        COALESCE(cs.sls_id, '')                                                         AS sls_id,
        CASE WHEN NULLIF(cs.sls_id, '') IS NOT NULL 
             THEN cs.sls_id || ' - ' || COALESCE(sh.sls_nm, '') ELSE '' END             AS sls_nm,

        COALESCE(cs.group_channel_id, '')                                               AS group_channel_id,
        CASE WHEN NULLIF(cs.group_channel_id, '') IS NOT NULL 
             THEN cs.group_channel_id || ' - ' || COALESCE(cs.group_channel_nm, '') ELSE '' END AS group_channel_nm,

        COALESCE(cs.channel_id, '')                                                     AS channel_id,
        CASE WHEN NULLIF(cs.channel_id, '') IS NOT NULL 
             THEN cs.channel_id || ' - ' || COALESCE(cs.channel_nm, '') ELSE '' END     AS channel_nm,

        COALESCE(cs.cust_id, '')                                                        AS cust_id,
        CASE WHEN NULLIF(cs.cust_id, '') IS NOT NULL 
             THEN cs.cust_id || ' - ' || COALESCE(cs.cust_nm, '') ELSE '' END           AS cust_nm
    FROM (
        SELECT *
        FROM bift.dim_fcustsls_staging
        WHERE tahun   = 2026
          AND periode IN (4, 5)
    ) cs
    INNER JOIN bift.dim_salesman_hierarchy sh
            ON cs.distributor_id = sh.distributor_id
           AND cs.sls_id         = sh.sls_id
),

-- Raw transactions enriched with date -> cycle3 week + product detail (DEV filtered)
trx AS (
    SELECT
        COALESCE(s.subdist_id,       '')        AS distributor_id,
        COALESCE(s.slsno,            '')        AS sls_id,
        COALESCE(s.custno,           '')        AS cust_id,
        COALESCE(c."year"::numeric,   0)        AS tahun,
        COALESCE(c."period"::numeric, 0)        AS periode,
        COALESCE(c.week::numeric,     0)        AS week,
        COALESCE(s.inv_no,           '')        AS inv_no,

        COALESCE(s.pcode,            '')        AS pcode,
        CASE WHEN NULLIF(s.pcode, '') IS NOT NULL 
             THEN s.pcode || ' - ' || COALESCE(f.pcode_nm, '') ELSE '' END AS pcode_nm,

        COALESCE(f.subbrand_id,      '')        AS subbrand_id,
        CASE WHEN NULLIF(f.subbrand_id, '') IS NOT NULL 
             THEN f.subbrand_id || ' - ' || COALESCE(f.subbrand_nm, '') ELSE '' END AS subbrand_nm,

        COALESCE(s.inv_val,           0)        AS inv_val,
        COALESCE(
            s.inv_qty::numeric / NULLIF(f.convunit2 * f.convunit3, 0),
            0
        )                                       AS qty_carton
    FROM raw_ho.vfsales_det s
    INNER JOIN spx.m_cycle3 c
            ON s.ord_date::date = c.cdate::date
    LEFT JOIN bift.dim_product f
           ON s.pcode = f.pcode
    WHERE s.sts               = '905'
      AND c."year"::numeric   = 2026
      AND c."period"::numeric IN (4, 5)
),

-- Stream A: Non-purchasing CB Outlets
non_purchasing AS (
    SELECT
        cb.source_schema,
        cb.tahun,
        cb.periode,
        wb.week,

        -- Sales Hierarchy
        cb.sd_id, cb.sd_nm,
        cb.nsm_id, cb.nsm_nm,
        cb.grsm_id, cb.grsm_nm,
        cb.rsm_id, cb.rsm_nm,
        cb.ss_id, cb.ss_nm,
        cb.distributor_id, cb.distributor_nm,

        -- Salesforce
        cb.gsalesforce1_id, cb.gsalesforce1_nm,
        cb.gsalesforce2_id, cb.gsalesforce2_nm,
        cb.salesforce_id, cb.salesforce_nm,

        -- Salesman, Channel & Outlet
        cb.sls_id, cb.sls_nm,
        cb.group_channel_id, cb.group_channel_nm,
        cb.channel_id, cb.channel_nm,

        COALESCE(cc.classification_id, '')          AS classification_id,
        CASE WHEN NULLIF(cc.classification_id, '') IS NOT NULL 
             THEN cc.classification_id || ' - ' || COALESCE(dc.classification_nm, '') ELSE '' END AS classification_nm,

        cb.cust_id, cb.cust_nm,

        -- Placeholders for non-transacting outlets
        'N/A'                                       AS pcode,
        'N/A'                                       AS pcode_nm,
        'N/A'                                       AS subbrand_id,
        'N/A'                                       AS subbrand_nm,
        0                                           AS order_count,
        0::numeric                                  AS qty_carton,
        0::numeric                                  AS inv_val,
        0                                           AS is_transaction
    FROM cb_cover cb
    INNER JOIN week_bridge wb
            ON wb.tahun   = cb.tahun
           AND wb.periode = cb.periode
    LEFT JOIN raw_ficom_m2.m_channel_classifications cc
           ON cb.channel_id    = cc.channel_id
          AND cb.source_schema = 'm2'
    LEFT JOIN bift.dim_classifications dc
           ON cc.classification_id = dc.classification_id
    WHERE NOT EXISTS (
        SELECT 1
        FROM trx t
        WHERE t.distributor_id = cb.distributor_id
          AND t.sls_id         = cb.sls_id
          AND t.cust_id        = cb.cust_id
          AND t.tahun          = cb.tahun
          AND t.periode        = cb.periode
    )
    GROUP BY
        cb.source_schema, cb.tahun, cb.periode, wb.week,
        cb.sd_id, cb.sd_nm, cb.nsm_id, cb.nsm_nm, cb.grsm_id, cb.grsm_nm,
        cb.rsm_id, cb.rsm_nm, cb.ss_id, cb.ss_nm, cb.distributor_id, cb.distributor_nm,
        cb.gsalesforce1_id, cb.gsalesforce1_nm, cb.gsalesforce2_id, cb.gsalesforce2_nm,
        cb.salesforce_id, cb.salesforce_nm, cb.sls_id, cb.sls_nm,
        cb.group_channel_id, cb.group_channel_nm, cb.channel_id, cb.channel_nm,
        COALESCE(cc.classification_id, ''),
        CASE WHEN NULLIF(cc.classification_id, '') IS NOT NULL 
             THEN cc.classification_id || ' - ' || COALESCE(dc.classification_nm, '') ELSE '' END,
        cb.cust_id, cb.cust_nm
),

-- Stream B: Real Transactions
purchasing AS (
    SELECT
        cb.source_schema,
        cb.tahun,
        cb.periode,
        t.week,

        -- Sales Hierarchy
        cb.sd_id, cb.sd_nm,
        cb.nsm_id, cb.nsm_nm,
        cb.grsm_id, cb.grsm_nm,
        cb.rsm_id, cb.rsm_nm,
        cb.ss_id, cb.ss_nm,
        cb.distributor_id, cb.distributor_nm,

        -- Salesforce
        cb.gsalesforce1_id, cb.gsalesforce1_nm,
        cb.gsalesforce2_id, cb.gsalesforce2_nm,
        cb.salesforce_id, cb.salesforce_nm,

        -- Salesman, Channel & Outlet
        cb.sls_id, cb.sls_nm,
        cb.group_channel_id, cb.group_channel_nm,
        cb.channel_id, cb.channel_nm,

        COALESCE(cc.classification_id, '')          AS classification_id,
        CASE WHEN NULLIF(cc.classification_id, '') IS NOT NULL 
             THEN cc.classification_id || ' - ' || COALESCE(dc.classification_nm, '') ELSE '' END AS classification_nm,

        cb.cust_id, cb.cust_nm,

        -- Product Detail
        t.pcode, t.pcode_nm,
        t.subbrand_id, t.subbrand_nm,

        COUNT(DISTINCT t.inv_no)                    AS order_count,
        COALESCE(SUM(t.qty_carton), 0)              AS qty_carton,
        COALESCE(SUM(t.inv_val), 0)                 AS inv_val,
        1                                           AS is_transaction
    FROM cb_cover cb
    INNER JOIN trx t
            ON cb.distributor_id = t.distributor_id
           AND cb.sls_id         = t.sls_id
           AND cb.cust_id        = t.cust_id
           AND cb.tahun          = t.tahun
           AND cb.periode        = t.periode
    LEFT JOIN raw_ficom_m2.m_channel_classifications cc
           ON cb.channel_id    = cc.channel_id
          AND cb.source_schema = 'm2'
    LEFT JOIN bift.dim_classifications dc
           ON cc.classification_id = dc.classification_id
    GROUP BY
        cb.source_schema, cb.tahun, cb.periode, t.week,
        cb.sd_id, cb.sd_nm, cb.nsm_id, cb.nsm_nm, cb.grsm_id, cb.grsm_nm,
        cb.rsm_id, cb.rsm_nm, cb.ss_id, cb.ss_nm, cb.distributor_id, cb.distributor_nm,
        cb.gsalesforce1_id, cb.gsalesforce1_nm, cb.gsalesforce2_id, cb.gsalesforce2_nm,
        cb.salesforce_id, cb.salesforce_nm, cb.sls_id, cb.sls_nm,
        cb.group_channel_id, cb.group_channel_nm, cb.channel_id, cb.channel_nm,
        COALESCE(cc.classification_id, ''),
        CASE WHEN NULLIF(cc.classification_id, '') IS NOT NULL 
             THEN cc.classification_id || ' - ' || COALESCE(dc.classification_nm, '') ELSE '' END,
        cb.cust_id, cb.cust_nm,
        t.pcode, t.pcode_nm, t.subbrand_id, t.subbrand_nm
)

SELECT * FROM non_purchasing
UNION ALL
SELECT * FROM purchasing
