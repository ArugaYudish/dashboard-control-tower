{{
    config(
        schema='bift',
        materialized='table',
        alias='gold_npl_by_hierarchy_dev',
        pre_hook="SET LOCAL work_mem = '256MB';",
        indexes=[
          {'columns': ['tahun', 'periode'], 'type': 'btree'},
          {'columns': ['distributor_id'], 'type': 'btree'},
          {'columns': ['pcode'], 'type': 'btree'},
          {'columns': ['subbrand_id'], 'type': 'btree'},
          {'columns': ['salesforce_id'], 'type': 'btree'},
          {'columns': ['channel_id'], 'type': 'btree'}
        ]
    )
}}

WITH 

-- STEP 0: Exact CB Cover per Distributor, Salesforce & Channel (1,211 for 103481)
distributor_channel_cb AS (
    SELECT
        tahun, periode,
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm, ss_id, ss_nm,
        distributor_id, distributor_nm,
        salesforce_id, salesforce_nm, gsalesforce_id, gsalesforce_nm,
        group_channel_id, group_channel_nm, channel_id, channel_nm,
        COUNT(DISTINCT cust_id) AS cb_cover
    FROM bift.silver_npl_by_hierarchy_dev
    GROUP BY
        tahun, periode,
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm, ss_id, ss_nm,
        distributor_id, distributor_nm,
        salesforce_id, salesforce_nm, gsalesforce_id, gsalesforce_nm,
        group_channel_id, group_channel_nm, channel_id, channel_nm
),

-- STEP 1A: All-Products Rollup (order_count across ALL products per outlet)
outlet_summary_all AS (
    SELECT
        tahun, periode,
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm, ss_id, ss_nm,
        distributor_id, distributor_nm,
        salesforce_id, salesforce_nm, gsalesforce_id, gsalesforce_nm,
        group_channel_id, group_channel_nm, channel_id, channel_nm,
        cust_id,
        'ALL' AS pcode, 'ALL Products' AS pcode_nm,
        'ALL' AS subbrand_id, 'ALL Subbrands' AS subbrand_nm,

        COUNT(DISTINCT inv_no)                                          AS order_count,
        SUM(COALESCE(qty_carton, 0))                                    AS qty_carton,
        SUM(CASE WHEN week = 14 THEN COALESCE(inv_val, 0) ELSE 0 END)   AS omset_w14,
        SUM(CASE WHEN week = 15 THEN COALESCE(inv_val, 0) ELSE 0 END)   AS omset_w15,
        SUM(CASE WHEN week = 16 THEN COALESCE(inv_val, 0) ELSE 0 END)   AS omset_w16,
        SUM(CASE WHEN week = 17 THEN COALESCE(inv_val, 0) ELSE 0 END)   AS omset_w17,
        SUM(CASE WHEN week = 18 THEN COALESCE(inv_val, 0) ELSE 0 END)   AS omset_w18,
        SUM(COALESCE(inv_val, 0))                                       AS total_omset
    FROM bift.silver_npl_by_hierarchy_dev
    GROUP BY
        tahun, periode,
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm, ss_id, ss_nm,
        distributor_id, distributor_nm,
        salesforce_id, salesforce_nm, gsalesforce_id, gsalesforce_nm,
        group_channel_id, group_channel_nm, channel_id, channel_nm,
        cust_id
),

-- STEP 1B: Per-PCode Rollup (order_count for specific pcode per outlet)
outlet_summary_by_pcode AS (
    SELECT
        tahun, periode,
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm, ss_id, ss_nm,
        distributor_id, distributor_nm,
        salesforce_id, salesforce_nm, gsalesforce_id, gsalesforce_nm,
        group_channel_id, group_channel_nm, channel_id, channel_nm,
        cust_id,
        pcode, pcode_nm,
        subbrand_id, subbrand_nm,

        COUNT(DISTINCT inv_no)                                          AS order_count,
        SUM(COALESCE(qty_carton, 0))                                    AS qty_carton,
        SUM(CASE WHEN week = 14 THEN COALESCE(inv_val, 0) ELSE 0 END)   AS omset_w14,
        SUM(CASE WHEN week = 15 THEN COALESCE(inv_val, 0) ELSE 0 END)   AS omset_w15,
        SUM(CASE WHEN week = 16 THEN COALESCE(inv_val, 0) ELSE 0 END)   AS omset_w16,
        SUM(CASE WHEN week = 17 THEN COALESCE(inv_val, 0) ELSE 0 END)   AS omset_w17,
        SUM(CASE WHEN week = 18 THEN COALESCE(inv_val, 0) ELSE 0 END)   AS omset_w18,
        SUM(COALESCE(inv_val, 0))                                       AS total_omset
    FROM bift.silver_npl_by_hierarchy_dev
    WHERE pcode IS NOT NULL
    GROUP BY
        tahun, periode,
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm, ss_id, ss_nm,
        distributor_id, distributor_nm,
        salesforce_id, salesforce_nm, gsalesforce_id, gsalesforce_nm,
        group_channel_id, group_channel_nm, channel_id, channel_nm,
        cust_id, pcode, pcode_nm, subbrand_id, subbrand_nm
),

-- Combine both levels
combined_outlet_summary AS (
    SELECT * FROM outlet_summary_all
    UNION ALL
    SELECT * FROM outlet_summary_by_pcode
)

-- STEP 2: Aggregate to Hierarchy + Channel + Product Level
SELECT
    s.tahun, s.periode,
    s.sd_id, s.sd_nm, s.nsm_id, s.nsm_nm, s.grsm_id, s.grsm_nm, s.rsm_id, s.rsm_nm, s.ss_id, s.ss_nm,
    s.distributor_id, s.distributor_nm,
    s.salesforce_id, s.salesforce_nm, s.gsalesforce_id, s.gsalesforce_nm,
    s.group_channel_id, s.group_channel_nm, s.channel_id, s.channel_nm,
    s.pcode, s.pcode_nm, s.subbrand_id, s.subbrand_nm,

    -- 1. CB Cover (Exact 1,211 for Distributor 103481)
    MAX(cb.cb_cover)                                                        AS cb_cover,

    -- 2. OA
    COUNT(DISTINCT CASE WHEN s.order_count >= 1 THEN s.cust_id END)         AS oa,

    -- 3. %OA
    ROUND(
        COUNT(DISTINCT CASE WHEN s.order_count >= 1 THEN s.cust_id END)::numeric 
        / NULLIF(MAX(cb.cb_cover), 0) * 100, 2
    )                                                                       AS oa_percent,

    -- 4. Dropsize
    ROUND(
        SUM(s.qty_carton)::numeric 
        / NULLIF(COUNT(DISTINCT CASE WHEN s.order_count >= 1 THEN s.cust_id END), 0), 2
    )                                                                       AS total_dropsize,

    -- 5-10. Repeat Buckets
    COUNT(DISTINCT CASE WHEN s.order_count = 1  THEN s.cust_id END)         AS non_repeat,
    COUNT(DISTINCT CASE WHEN s.order_count = 2  THEN s.cust_id END)         AS t2,
    COUNT(DISTINCT CASE WHEN s.order_count = 3  THEN s.cust_id END)         AS t3,
    COUNT(DISTINCT CASE WHEN s.order_count = 4  THEN s.cust_id END)         AS t4,
    COUNT(DISTINCT CASE WHEN s.order_count = 5  THEN s.cust_id END)         AS t5,
    COUNT(DISTINCT CASE WHEN s.order_count >= 6 THEN s.cust_id END)         AS t6,

    -- 11. % Repeat
    ROUND(
        COUNT(DISTINCT CASE WHEN s.order_count >= 2 THEN s.cust_id END)::numeric 
        / NULLIF(COUNT(DISTINCT CASE WHEN s.order_count >= 1 THEN s.cust_id END), 0) * 100, 2
    )                                                                       AS percent_repeat,

    -- 12. Weekly Omsets
    SUM(s.omset_w14)                                                        AS omset_w14,
    SUM(s.omset_w15)                                                        AS omset_w15,
    SUM(s.omset_w16)                                                        AS omset_w16,
    SUM(s.omset_w17)                                                        AS omset_w17,
    SUM(s.omset_w18)                                                        AS omset_w18,
    SUM(s.total_omset)                                                      AS total_omset

FROM combined_outlet_summary s
INNER JOIN distributor_channel_cb cb
        ON cb.tahun          = s.tahun
       AND cb.periode        = s.periode
       AND cb.distributor_id = s.distributor_id
       AND cb.salesforce_id  = s.salesforce_id
       AND cb.channel_id     = s.channel_id
GROUP BY
    s.tahun, s.periode,
    s.sd_id, s.sd_nm, s.nsm_id, s.nsm_nm, s.grsm_id, s.grsm_nm, s.rsm_id, s.rsm_nm, s.ss_id, s.ss_nm,
    s.distributor_id, s.distributor_nm,
    s.salesforce_id, s.salesforce_nm, s.gsalesforce_id, s.gsalesforce_nm,
    s.group_channel_id, s.group_channel_nm, s.channel_id, s.channel_nm,
    s.pcode, s.pcode_nm, s.subbrand_id, s.subbrand_nm
