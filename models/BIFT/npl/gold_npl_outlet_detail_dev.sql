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
          {'columns': ['classification_id'], 'type': 'btree'},
          {'columns': ['gdiv_id'], 'type': 'btree'}
        ]
    )
}}

-- DEV/TESTING ONLY: Direct Gold Outlet Detail Model (tahun = 2026)
-- Built from Silver OA Performance (silver_oa_performance).
-- Pre-formats all _nm columns as "ID - Name" (or '' if ID is null/empty).
-- Guaranteed 100% NULL-FREE across all columns.

WITH week_bridge AS (
    SELECT DISTINCT
        COALESCE("year"::numeric, 0)     AS tahun,
        COALESCE("period"::numeric, 0)   AS periode,
        COALESCE(week::numeric, 0)       AS week
    FROM spx.m_cycle3
    WHERE "year"::numeric   = 2026
),

-- Stream A: Non-purchasing Outlets from Silver OA Performance
non_purchasing AS (
    SELECT
        COALESCE(s.source_schema, '')                                                   AS source_schema,
        COALESCE(s.tahun, 0)                                                            AS tahun,
        COALESCE(s.periode, 0)                                                          AS periode,
        COALESCE(wb.week, 0)                                                            AS week,

        -- Grand Division
        COALESCE(s.gdiv_id, '')                                                         AS gdiv_id,
        CASE WHEN NULLIF(s.gdiv_id, '') IS NOT NULL 
             THEN s.gdiv_id || ' - ' || COALESCE(s.gdiv_nm, '') ELSE '' END            AS gdiv_nm,

        -- Sales Hierarchy
        COALESCE(s.sd_id, '')                                                           AS sd_id,
        CASE WHEN NULLIF(s.sd_id, '') IS NOT NULL 
             THEN s.sd_id || ' - ' || COALESCE(s.sd_nm, '') ELSE '' END                AS sd_nm,

        COALESCE(s.nsm_id, '')                                                          AS nsm_id,
        CASE WHEN NULLIF(s.nsm_id, '') IS NOT NULL 
             THEN s.nsm_id || ' - ' || COALESCE(s.nsm_nm, '') ELSE '' END              AS nsm_nm,

        COALESCE(s.grsm_id, '')                                                         AS grsm_id,
        CASE WHEN NULLIF(s.grsm_id, '') IS NOT NULL 
             THEN s.grsm_id || ' - ' || COALESCE(s.grsm_nm, '') ELSE '' END            AS grsm_nm,

        COALESCE(s.rsm_id, '')                                                          AS rsm_id,
        CASE WHEN NULLIF(s.rsm_id, '') IS NOT NULL 
             THEN s.rsm_id || ' - ' || COALESCE(s.rsm_nm, '') ELSE '' END              AS rsm_nm,

        COALESCE(s.ss_id, '')                                                           AS ss_id,
        CASE WHEN NULLIF(s.ss_id, '') IS NOT NULL 
             THEN s.ss_id || ' - ' || COALESCE(s.ss_nm, '') ELSE '' END                AS ss_nm,

        COALESCE(s.distributor_id, '')                                                  AS distributor_id,
        CASE WHEN NULLIF(s.distributor_id, '') IS NOT NULL 
             THEN s.distributor_id || ' - ' || COALESCE(s.distributor_nm, '') ELSE '' END AS distributor_nm,

        -- Salesforce
        COALESCE(s.gsalesforce1_id, '')                                                 AS gsalesforce1_id,
        CASE WHEN NULLIF(s.gsalesforce1_id, '') IS NOT NULL 
             THEN s.gsalesforce1_id || ' - ' || COALESCE(s.gsalesforce1_nm, '') ELSE '' END AS gsalesforce1_nm,

        COALESCE(s.gsalesforce2_id, '')                                                 AS gsalesforce2_id,
        CASE WHEN NULLIF(s.gsalesforce2_id, '') IS NOT NULL 
             THEN s.gsalesforce2_id || ' - ' || COALESCE(s.gsalesforce2_nm, '') ELSE '' END AS gsalesforce2_nm,

        COALESCE(s.salesforce_id, '')                                                   AS salesforce_id,
        CASE WHEN NULLIF(s.salesforce_id, '') IS NOT NULL 
             THEN s.salesforce_id || ' - ' || COALESCE(s.salesforce_nm, '') ELSE '' END AS salesforce_nm,

        -- Salesman, Channel & Outlet
        COALESCE(s.sls_id, '')                                                          AS sls_id,
        CASE WHEN NULLIF(s.sls_id, '') IS NOT NULL 
             THEN s.sls_id || ' - ' || COALESCE(s.sls_nm, '') ELSE '' END              AS sls_nm,

        COALESCE(s.group_channel_id, '')                                                AS group_channel_id,
        CASE WHEN NULLIF(s.group_channel_id, '') IS NOT NULL 
             THEN s.group_channel_id || ' - ' || COALESCE(s.group_channel_nm, '') ELSE '' END AS group_channel_nm,

        COALESCE(s.channel_id, '')                                                      AS channel_id,
        CASE WHEN NULLIF(s.channel_id, '') IS NOT NULL 
             THEN s.channel_id || ' - ' || COALESCE(s.channel_nm, '') ELSE '' END      AS channel_nm,

        COALESCE(cc.classification_id, '')                                              AS classification_id,
        CASE WHEN NULLIF(cc.classification_id, '') IS NOT NULL 
             THEN cc.classification_id || ' - ' || COALESCE(dc.classification_nm, '') ELSE '' END AS classification_nm,

        COALESCE(s.cust_id, '')                                                         AS cust_id,
        CASE WHEN NULLIF(s.cust_id, '') IS NOT NULL 
             THEN s.cust_id || ' - ' || COALESCE(s.cust_nm, '') ELSE '' END            AS cust_nm,

        -- Placeholders for non-transacting outlets
        'N/A'                                       AS pcode,
        'N/A'                                       AS pcode_nm,
        'N/A'                                       AS subbrand_id,
        'N/A'                                       AS subbrand_nm,
        0                                           AS order_count,
        0::numeric                                  AS qty_carton,
        0::numeric                                  AS inv_val,
        0                                           AS is_transaction
    FROM (
        SELECT *
        FROM bift.silver_oa_performance
        WHERE is_transaction = 0
          AND tahun          = 2026
    ) s
    INNER JOIN week_bridge wb
            ON wb.tahun   = s.tahun
           AND wb.periode = s.periode
    LEFT JOIN raw_ficom_m2.m_channel_classifications cc
           ON s.channel_id    = cc.channel_id
          AND s.source_schema = 'm2'
    LEFT JOIN bift.dim_classifications dc
           ON cc.classification_id = dc.classification_id
    GROUP BY
        s.source_schema, s.tahun, s.periode, wb.week,
        s.gdiv_id, s.gdiv_nm,
        s.sd_id, s.sd_nm, s.nsm_id, s.nsm_nm, s.grsm_id, s.grsm_nm,
        s.rsm_id, s.rsm_nm, s.ss_id, s.ss_nm, s.distributor_id, s.distributor_nm,
        s.gsalesforce1_id, s.gsalesforce1_nm, s.gsalesforce2_id, s.gsalesforce2_nm,
        s.salesforce_id, s.salesforce_nm, s.sls_id, s.sls_nm,
        s.group_channel_id, s.group_channel_nm, s.channel_id, s.channel_nm,
        COALESCE(cc.classification_id, ''),
        CASE WHEN NULLIF(cc.classification_id, '') IS NOT NULL 
             THEN cc.classification_id || ' - ' || COALESCE(dc.classification_nm, '') ELSE '' END,
        s.cust_id, s.cust_nm
),

-- Stream B: Real Transactions from Silver OA Performance
purchasing AS (
    SELECT
        COALESCE(s.source_schema, '')                                                   AS source_schema,
        COALESCE(s.tahun, 0)                                                            AS tahun,
        COALESCE(s.periode, 0)                                                          AS periode,
        COALESCE(s.week, 0)                                                             AS week,

        -- Grand Division
        COALESCE(s.gdiv_id, '')                                                         AS gdiv_id,
        CASE WHEN NULLIF(s.gdiv_id, '') IS NOT NULL 
             THEN s.gdiv_id || ' - ' || COALESCE(s.gdiv_nm, '') ELSE '' END            AS gdiv_nm,

        -- Sales Hierarchy
        COALESCE(s.sd_id, '')                                                           AS sd_id,
        CASE WHEN NULLIF(s.sd_id, '') IS NOT NULL 
             THEN s.sd_id || ' - ' || COALESCE(s.sd_nm, '') ELSE '' END                AS sd_nm,

        COALESCE(s.nsm_id, '')                                                          AS nsm_id,
        CASE WHEN NULLIF(s.nsm_id, '') IS NOT NULL 
             THEN s.nsm_id || ' - ' || COALESCE(s.nsm_nm, '') ELSE '' END              AS nsm_nm,

        COALESCE(s.grsm_id, '')                                                         AS grsm_id,
        CASE WHEN NULLIF(s.grsm_id, '') IS NOT NULL 
             THEN s.grsm_id || ' - ' || COALESCE(s.grsm_nm, '') ELSE '' END            AS grsm_nm,

        COALESCE(s.rsm_id, '')                                                          AS rsm_id,
        CASE WHEN NULLIF(s.rsm_id, '') IS NOT NULL 
             THEN s.rsm_id || ' - ' || COALESCE(s.rsm_nm, '') ELSE '' END              AS rsm_nm,

        COALESCE(s.ss_id, '')                                                           AS ss_id,
        CASE WHEN NULLIF(s.ss_id, '') IS NOT NULL 
             THEN s.ss_id || ' - ' || COALESCE(s.ss_nm, '') ELSE '' END                AS ss_nm,

        COALESCE(s.distributor_id, '')                                                  AS distributor_id,
        CASE WHEN NULLIF(s.distributor_id, '') IS NOT NULL 
             THEN s.distributor_id || ' - ' || COALESCE(s.distributor_nm, '') ELSE '' END AS distributor_nm,

        -- Salesforce
        COALESCE(s.gsalesforce1_id, '')                                                 AS gsalesforce1_id,
        CASE WHEN NULLIF(s.gsalesforce1_id, '') IS NOT NULL 
             THEN s.gsalesforce1_id || ' - ' || COALESCE(s.gsalesforce1_nm, '') ELSE '' END AS gsalesforce1_nm,

        COALESCE(s.gsalesforce2_id, '')                                                 AS gsalesforce2_id,
        CASE WHEN NULLIF(s.gsalesforce2_id, '') IS NOT NULL 
             THEN s.gsalesforce2_id || ' - ' || COALESCE(s.gsalesforce2_nm, '') ELSE '' END AS gsalesforce2_nm,

        COALESCE(s.salesforce_id, '')                                                   AS salesforce_id,
        CASE WHEN NULLIF(s.salesforce_id, '') IS NOT NULL 
             THEN s.salesforce_id || ' - ' || COALESCE(s.salesforce_nm, '') ELSE '' END AS salesforce_nm,

        -- Salesman, Channel & Outlet
        COALESCE(s.sls_id, '')                                                          AS sls_id,
        CASE WHEN NULLIF(s.sls_id, '') IS NOT NULL 
             THEN s.sls_id || ' - ' || COALESCE(s.sls_nm, '') ELSE '' END              AS sls_nm,

        COALESCE(s.group_channel_id, '')                                                AS group_channel_id,
        CASE WHEN NULLIF(s.group_channel_id, '') IS NOT NULL 
             THEN s.group_channel_id || ' - ' || COALESCE(s.group_channel_nm, '') ELSE '' END AS group_channel_nm,

        COALESCE(s.channel_id, '')                                                      AS channel_id,
        CASE WHEN NULLIF(s.channel_id, '') IS NOT NULL 
             THEN s.channel_id || ' - ' || COALESCE(s.channel_nm, '') ELSE '' END      AS channel_nm,

        COALESCE(cc.classification_id, '')                                              AS classification_id,
        CASE WHEN NULLIF(cc.classification_id, '') IS NOT NULL 
             THEN cc.classification_id || ' - ' || COALESCE(dc.classification_nm, '') ELSE '' END AS classification_nm,

        COALESCE(s.cust_id, '')                                                         AS cust_id,
        CASE WHEN NULLIF(s.cust_id, '') IS NOT NULL 
             THEN s.cust_id || ' - ' || COALESCE(s.cust_nm, '') ELSE '' END            AS cust_nm,

        -- Product Detail
        COALESCE(s.pcode, '')                                                           AS pcode,
        CASE WHEN NULLIF(s.pcode, '') IS NOT NULL 
             THEN s.pcode || ' - ' || COALESCE(s.pcode_nm, '') ELSE '' END             AS pcode_nm,

        COALESCE(s.subbrand_id, '')                                                     AS subbrand_id,
        CASE WHEN NULLIF(s.subbrand_id, '') IS NOT NULL 
             THEN s.subbrand_id || ' - ' || COALESCE(s.subbrand_nm, '') ELSE '' END    AS subbrand_nm,

        COUNT(DISTINCT s.inv_no)                    AS order_count,
        COALESCE(SUM(s.qty_carton), 0)              AS qty_carton,
        COALESCE(SUM(s.inv_val), 0)                 AS inv_val,
        1                                           AS is_transaction
    FROM (
        SELECT *
        FROM bift.silver_oa_performance
        WHERE is_transaction = 1
          AND tahun          = 2026
    ) s
    LEFT JOIN raw_ficom_m2.m_channel_classifications cc
           ON s.channel_id    = cc.channel_id
          AND s.source_schema = 'm2'
    LEFT JOIN bift.dim_classifications dc
           ON cc.classification_id = dc.classification_id
    GROUP BY
        s.source_schema, s.tahun, s.periode, s.week,
        s.gdiv_id, s.gdiv_nm,
        s.sd_id, s.sd_nm, s.nsm_id, s.nsm_nm, s.grsm_id, s.grsm_nm,
        s.rsm_id, s.rsm_nm, s.ss_id, s.ss_nm, s.distributor_id, s.distributor_nm,
        s.gsalesforce1_id, s.gsalesforce1_nm, s.gsalesforce2_id, s.gsalesforce2_nm,
        s.salesforce_id, s.salesforce_nm, s.sls_id, s.sls_nm,
        s.group_channel_id, s.group_channel_nm, s.channel_id, s.channel_nm,
        COALESCE(cc.classification_id, ''),
        CASE WHEN NULLIF(cc.classification_id, '') IS NOT NULL 
             THEN cc.classification_id || ' - ' || COALESCE(dc.classification_nm, '') ELSE '' END,
        s.cust_id, s.cust_nm,
        s.pcode, s.pcode_nm, s.subbrand_id, s.subbrand_nm
)

SELECT * FROM non_purchasing
UNION ALL
SELECT * FROM purchasing

