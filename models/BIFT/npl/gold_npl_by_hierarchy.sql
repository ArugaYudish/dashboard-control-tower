{{
    config(
        schema='bift',
        materialized='table',
        alias='gold_npl_by_hierarchy',
        pre_hook="SET LOCAL work_mem = '512MB';",
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

-- STEP 0: Compute CB Cover grouped by Hierarchy, Salesforce, and Channel
-- Since every cust_id belongs to EXACTLY 1 channel & 1 salesforce in a period, summing cb_cover across channels = distributor total (MECE)
distributor_channel_cb AS (
    SELECT
        tahun,
        periode,

        -- Hierarchy
        sd_id,
        sd_nm,
        nsm_id,
        nsm_nm,
        grsm_id,
        grsm_nm,
        rsm_id,
        rsm_nm,
        ss_id,
        ss_nm,
        distributor_id,
        distributor_nm,

        -- Salesforce & Channel
        salesforce_id,
        salesforce_nm,
        gsalesforce_id,
        gsalesforce_nm,
        group_channel_id,
        group_channel_nm,
        channel_id,
        channel_nm,

        COUNT(DISTINCT cust_id)                                         AS cb_cover

    FROM {{ ref('silver_npl_by_hierarchy') }}
    GROUP BY
        tahun,
        periode,
        sd_id,
        sd_nm,
        nsm_id,
        nsm_nm,
        grsm_id,
        grsm_nm,
        rsm_id,
        rsm_nm,
        ss_id,
        ss_nm,
        distributor_id,
        distributor_nm,
        salesforce_id,
        salesforce_nm,
        gsalesforce_id,
        gsalesforce_nm,
        group_channel_id,
        group_channel_nm,
        channel_id,
        channel_nm
),

-- STEP 1: Summarize transaction count and values at outlet + product level per period
outlet_pcode_summary AS (
    SELECT
        tahun,
        periode,

        -- Hierarchy
        sd_id,
        sd_nm,
        nsm_id,
        nsm_nm,
        grsm_id,
        grsm_nm,
        rsm_id,
        rsm_nm,
        ss_id,
        ss_nm,

        -- Distributor
        distributor_id,
        distributor_nm,

        -- Salesforce
        salesforce_id,
        salesforce_nm,
        gsalesforce_id,
        gsalesforce_nm,

        -- Channel
        group_channel_id,
        group_channel_nm,
        channel_id,
        channel_nm,

        -- Customer
        cust_id,

        -- Product
        pcode,
        pcode_nm,
        subbrand_id,
        subbrand_nm,

        -- Invoice count for this outlet+pcode across period
        COUNT(DISTINCT inv_no)                                          AS order_count,
        SUM(COALESCE(qty_carton, 0))                                    AS qty_carton,

        -- Pre-pivoted weekly omsets
        SUM(CASE WHEN week = 1 THEN COALESCE(inv_val, 0) ELSE 0 END)    AS omset_w1,
        SUM(CASE WHEN week = 2 THEN COALESCE(inv_val, 0) ELSE 0 END)    AS omset_w2,
        SUM(CASE WHEN week = 3 THEN COALESCE(inv_val, 0) ELSE 0 END)    AS omset_w3,
        SUM(CASE WHEN week = 4 THEN COALESCE(inv_val, 0) ELSE 0 END)    AS omset_w4,
        SUM(CASE WHEN week = 5 THEN COALESCE(inv_val, 0) ELSE 0 END)    AS omset_w5,
        SUM(COALESCE(inv_val, 0))                                       AS total_omset

    FROM {{ ref('silver_npl_by_hierarchy') }}
    GROUP BY
        tahun,
        periode,
        sd_id,
        sd_nm,
        nsm_id,
        nsm_nm,
        grsm_id,
        grsm_nm,
        rsm_id,
        rsm_nm,
        ss_id,
        ss_nm,
        distributor_id,
        distributor_nm,
        salesforce_id,
        salesforce_nm,
        gsalesforce_id,
        gsalesforce_nm,
        group_channel_id,
        group_channel_nm,
        channel_id,
        channel_nm,
        cust_id,
        pcode,
        pcode_nm,
        subbrand_id,
        subbrand_nm
)

-- STEP 2: Join distributor_channel_cb and pre-compute Gold metrics
SELECT
    s.tahun,
    s.periode,

    -- Hierarchy
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

    -- Salesforce
    s.salesforce_id,
    s.salesforce_nm,
    s.gsalesforce_id,
    s.gsalesforce_nm,

    -- Channel
    s.group_channel_id,
    s.group_channel_nm,
    s.channel_id,
    s.channel_nm,

    -- Product
    s.pcode,
    s.pcode_nm,
    s.subbrand_id,
    s.subbrand_nm,

    -- 1. CB Cover (Exact CB Cover for this specific hierarchy, salesforce & channel combination)
    MAX(cb.cb_cover)                                                        AS cb_cover,

    -- 2. OA (Total distinct outlets with at least 1 order for this product)
    COUNT(DISTINCT CASE WHEN s.order_count >= 1 THEN s.cust_id END)         AS oa,

    -- 3. %OA = (OA / CB Cover) * 100
    ROUND(
        (COUNT(DISTINCT CASE WHEN s.order_count >= 1 THEN s.cust_id END)::numeric 
         / NULLIF(MAX(cb.cb_cover), 0)) * 100, 
        2
    )                                                                       AS oa_percent,

    -- 4. Total Dropsize (Qty Carton / OA)
    ROUND(
        SUM(s.qty_carton)::numeric 
        / NULLIF(COUNT(DISTINCT CASE WHEN s.order_count >= 1 THEN s.cust_id END), 0), 
        2
    )                                                                       AS total_dropsize,

    -- 5. Non-Repeat (Outlets with 1 order)
    COUNT(DISTINCT CASE WHEN s.order_count = 1 THEN s.cust_id END)          AS non_repeat,

    -- 6. T2 (Outlets with 2 orders)
    COUNT(DISTINCT CASE WHEN s.order_count = 2 THEN s.cust_id END)          AS t2,

    -- 7. T3 (Outlets with 3 orders)
    COUNT(DISTINCT CASE WHEN s.order_count = 3 THEN s.cust_id END)          AS t3,

    -- 8. T4 (Outlets with 4 orders)
    COUNT(DISTINCT CASE WHEN s.order_count = 4 THEN s.cust_id END)          AS t4,

    -- 9. T5 (Outlets with 5 orders)
    COUNT(DISTINCT CASE WHEN s.order_count = 5 THEN s.cust_id END)          AS t5,

    -- 10. T6 (Outlets with 6 or more orders)
    COUNT(DISTINCT CASE WHEN s.order_count >= 6 THEN s.cust_id END)         AS t6,

    -- 11. Percent Repeat ((T2 + T3 + T4 + T5 + T6) / OA * 100)
    ROUND(
        (COUNT(DISTINCT CASE WHEN s.order_count >= 2 THEN s.cust_id END)::numeric 
         / NULLIF(COUNT(DISTINCT CASE WHEN s.order_count >= 1 THEN s.cust_id END), 0)) * 100, 
        2
    )                                                                       AS percent_repeat,

    -- 12. Pre-pivoted Weekly Omsets
    SUM(s.omset_w1)                                                         AS omset_w1,
    SUM(s.omset_w2)                                                         AS omset_w2,
    SUM(s.omset_w3)                                                         AS omset_w3,
    SUM(s.omset_w4)                                                         AS omset_w4,
    SUM(s.omset_w5)                                                         AS omset_w5,
    SUM(s.total_omset)                                                      AS total_omset

FROM outlet_pcode_summary s
INNER JOIN distributor_channel_cb cb
        ON cb.tahun          = s.tahun
       AND cb.periode        = s.periode
       AND cb.distributor_id = s.distributor_id
       AND cb.salesforce_id  = s.salesforce_id
       AND cb.channel_id     = s.channel_id
GROUP BY
    s.tahun,
    s.periode,
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
    s.salesforce_id,
    s.salesforce_nm,
    s.gsalesforce_id,
    s.gsalesforce_nm,
    s.group_channel_id,
    s.group_channel_nm,
    s.channel_id,
    s.channel_nm,
    s.pcode,
    s.pcode_nm,
    s.subbrand_id,
    s.subbrand_nm
