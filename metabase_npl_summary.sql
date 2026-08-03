-- Metabase SQL Query for NPL Summary Dashboard (Dynamic Week Breakdown)
-- Source: bift.gold_npl_outlet_summary_dev (or bift.gold_npl_outlet_summary in production)
-- Filters: {{tahun}} and {{weekFrom}} / {{weekTo}} (No period filter needed)

WITH outlet_orders AS (
    SELECT
        ss_id,
        distributor_id,
        cust_id,
        week,

        -- 1. Orders count for selected pcodes/subbrands in the selected week range
        SUM(
            CASE 
                WHEN 1=1
                [[ AND pcode IN ({{pcodes}}) ]]
                [[ AND subbrand_id IN ({{subbrands}}) ]]
                THEN order_count 
                ELSE 0 
            END
        )                                                               AS pcode_order_count,

        -- 2. Qty carton for selected pcodes/subbrands
        SUM(
            CASE 
                WHEN 1=1
                [[ AND pcode IN ({{pcodes}}) ]]
                [[ AND subbrand_id IN ({{subbrands}}) ]]
                THEN qty_carton 
                ELSE 0 
            END
        )                                                               AS pcode_qty_carton,

        -- 3. Omset for selected pcodes/subbrands
        SUM(
            CASE 
                WHEN 1=1
                [[ AND pcode IN ({{pcodes}}) ]]
                [[ AND subbrand_id IN ({{subbrands}}) ]]
                THEN inv_val 
                ELSE 0 
            END
        )                                                               AS week_omset,

        -- 4. Retrieve parent sales hierarchy attributes (Zero CPU overhead via MAX)
        MAX(ss_nm)                                                      AS ss_nm,
        MAX(rsm_id)                                                     AS rsm_id,
        MAX(rsm_nm)                                                     AS rsm_nm,
        MAX(grsm_id)                                                    AS grsm_id,
        MAX(grsm_nm)                                                    AS grsm_nm,
        MAX(nsm_id)                                                     AS nsm_id,
        MAX(nsm_nm)                                                     AS nsm_nm,
        MAX(sd_id)                                                      AS sd_id,
        MAX(sd_nm)                                                      AS sd_nm,
        MAX(distributor_nm)                                             AS distributor_nm

    FROM bift.gold_npl_outlet_summary_dev
    WHERE 1=1
      [[ AND tahun = {{tahun}} ]]
      [[ AND week BETWEEN {{weekFrom}} AND {{weekTo}} ]]
      [[ AND distributor_id IN ({{distributor_ids}}) ]]
      [[ AND rsm_id IN ({{rsm_ids}}) ]]
      [[ AND ss_id IN ({{ss_ids}}) ]]
      [[ AND channel_id IN ({{channel_ids}}) ]]
      [[ AND salesforce_id IN ({{salesforce_ids}}) ]]

    GROUP BY ss_id, distributor_id, cust_id, week
)

SELECT
    -- Sales Hierarchy Output (SS -> RSM -> GRSM -> NSM -> SD)
    MAX(sd_id)                                                          AS sd_id,
    MAX(sd_nm)                                                          AS sd_nm,
    MAX(nsm_id)                                                         AS nsm_id,
    MAX(nsm_nm)                                                         AS nsm_nm,
    MAX(grsm_id)                                                        AS grsm_id,
    MAX(grsm_nm)                                                        AS grsm_nm,
    MAX(rsm_id)                                                         AS rsm_id,
    MAX(rsm_nm)                                                         AS rsm_nm,
    ss_id,
    MAX(ss_nm)                                                          AS ss_nm,
    distributor_id,
    MAX(distributor_nm)                                                 AS distributor_nm,
    week,

    -- 1. CB Cover (Exact count of covered outlets for this week)
    COUNT(DISTINCT cust_id)                                             AS cb_cover,

    -- 2. OA (Active outlets for selected products in this week)
    COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END)   AS oa,

    -- 3. %OA = (OA / CB Cover) * 100
    ROUND(
        (COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END)::numeric 
         / NULLIF(COUNT(DISTINCT cust_id), 0)) * 100, 
        2
    )                                                                   AS oa_percent,

    -- 4. Total Dropsize (Carton Qty / OA)
    ROUND(
        SUM(pcode_qty_carton)::numeric 
        / NULLIF(COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END), 0), 
        2
    )                                                                   AS total_dropsize,

    -- 5–10. Deduplicated Repeat Order Buckets
    COUNT(DISTINCT CASE WHEN pcode_order_count = 1  THEN cust_id END)   AS non_repeat,
    COUNT(DISTINCT CASE WHEN pcode_order_count = 2  THEN cust_id END)   AS t2,
    COUNT(DISTINCT CASE WHEN pcode_order_count = 3  THEN cust_id END)   AS t3,
    COUNT(DISTINCT CASE WHEN pcode_order_count = 4  THEN cust_id END)   AS t4,
    COUNT(DISTINCT CASE WHEN pcode_order_count = 5  THEN cust_id END)   AS t5,
    COUNT(DISTINCT CASE WHEN pcode_order_count >= 6 THEN cust_id END)   AS t6,

    -- 11. % Repeat = ((T2 + T3 + T4 + T5 + T6) / OA) * 100
    ROUND(
        (COUNT(DISTINCT CASE WHEN pcode_order_count >= 2 THEN cust_id END)::numeric 
         / NULLIF(COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END), 0)) * 100, 
        2
    )                                                                   AS percent_repeat,

    -- 12. Weekly Omset
    SUM(week_omset)                                                     AS omset

FROM outlet_orders
GROUP BY ss_id, distributor_id, week
ORDER BY ss_id, distributor_id, week;
