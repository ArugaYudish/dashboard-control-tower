{{
    config(
        schema='bift',
        materialized='table',
        alias='gold_npl_outlet_summary_dev',
        pre_hook="SET LOCAL work_mem = '256MB';",
        indexes=[
          {'columns': ['tahun', 'periode', 'week', 'distributor_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'distributor_id'], 'type': 'btree'},
          {'columns': ['distributor_id', 'cust_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'pcode'], 'type': 'btree'}
        ]
    )
}}

-- DEV/TESTING ONLY: Unified single Gold table at Outlet + Product + Week grain

SELECT
    tahun,
    periode,
    week,

    -- Sales Hierarchy
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

    -- Customer / Outlet
    cust_id,
    cust_nm,

    -- Product
    pcode,
    pcode_nm,
    subbrand_id,
    subbrand_nm,

    -- Pre-aggregated metrics at Outlet + Product + Week grain
    COUNT(DISTINCT inv_no)                                          AS order_count,
    SUM(COALESCE(qty_carton, 0))                                    AS qty_carton,
    SUM(COALESCE(inv_val, 0))                                       AS inv_val

FROM bift.silver_npl_by_hierarchy_dev
GROUP BY
    tahun,
    periode,
    week,
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
    cust_nm,
    pcode,
    pcode_nm,
    subbrand_id,
    subbrand_nm
