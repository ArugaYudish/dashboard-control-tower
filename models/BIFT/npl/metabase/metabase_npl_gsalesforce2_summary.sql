-- Metabase SQL Query: NPL Breakdown Summary by Group Salesforce 2 (gsalesforce2)
-- Source: bift.gold_npl_by_gsalesforce2_dev (or bift.gold_npl_by_gsalesforce2 in production)
-- Output: SD | NSM | GRSM | RSM | SS | Distributor | Break By (gsalesforce2_id - gsalesforce2_nm) | cb_cover | oa | %oa | total_dropsize | non_repeat | t2 | t3 | t4 | t5 | t6 | percent_repeat

WITH outlet_orders AS (
    SELECT
        ss_id,
        distributor_id,
        gsalesforce2_id,
        gsalesforce2_nm,
        cust_id,

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

        -- 3. Retrieve parent sales hierarchy attributes (Zero CPU overhead via MAX)
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

    FROM bift.gold_npl_by_gsalesforce2_dev
    WHERE 1=1
      [[ AND tahun = {{tahun}}::numeric ]]
      [[ AND periode BETWEEN COALESCE(NULLIF('{{periodFrom}}', ''), '1')::numeric AND COALESCE(NULLIF('{{periodTo}}', ''), '13')::numeric ]]
      [[ AND week BETWEEN COALESCE(NULLIF('{{weekFrom}}', ''), '1')::numeric AND COALESCE(NULLIF('{{weekTo}}', ''), '53')::numeric ]]
      [[ AND sd_id IN ({{sd_ids}}) ]]
      [[ AND nsm_id IN ({{nsm_ids}}) ]]
      [[ AND grsm_id IN ({{grsm_ids}}) ]]
      [[ AND rsm_id IN ({{rsm_ids}}) ]]
      [[ AND ss_id IN ({{ss_ids}}) ]]
      [[ AND distributor_id IN ({{distributor_ids}}) ]]
      [[ AND gsalesforce2_id IN ({{gsalesforce2_ids}}) ]]

    GROUP BY ss_id, distributor_id, gsalesforce2_id, gsalesforce2_nm, cust_id
)

SELECT
    -- Concatenated Sales Hierarchy Output
    CASE WHEN MAX(sd_id) IS NOT NULL THEN CONCAT(MAX(sd_id), ' - ', MAX(sd_nm)) ELSE NULL END                      AS "SD",
    CASE WHEN MAX(nsm_id) IS NOT NULL THEN CONCAT(MAX(nsm_id), ' - ', MAX(nsm_nm)) ELSE NULL END                  AS "NSM",
    CASE WHEN MAX(grsm_id) IS NOT NULL THEN CONCAT(MAX(grsm_id), ' - ', MAX(grsm_nm)) ELSE NULL END               AS "GRSM",
    CASE WHEN MAX(rsm_id) IS NOT NULL THEN CONCAT(MAX(rsm_id), ' - ', MAX(rsm_nm)) ELSE NULL END                  AS "RSM",
    CASE WHEN ss_id IS NOT NULL THEN CONCAT(ss_id, ' - ', MAX(ss_nm)) ELSE NULL END                                AS "SS",
    CASE WHEN distributor_id IS NOT NULL THEN CONCAT(distributor_id, ' - ', MAX(distributor_nm)) ELSE NULL END    AS "Distributor",

    -- Break By Column (gsalesforce2_id - gsalesforce2_nm, NULL for unmapped)
    CASE 
        WHEN gsalesforce2_id IS NOT NULL 
        THEN CONCAT(gsalesforce2_id, ' - ', gsalesforce2_nm)
        ELSE NULL 
    END                                                                 AS "Break By",

    -- 1. CB Cover (Exact count of covered outlets for selected week range)
    COUNT(DISTINCT cust_id)                                             AS "CB Cover",

    -- 2. OA (Active outlets for selected products in selected week range)
    COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END)   AS "OA",

    -- 3. %OA = (OA / CB Cover) * 100
    ROUND(
        (COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END)::numeric 
         / NULLIF(COUNT(DISTINCT cust_id), 0)) * 100, 
        2
    )                                                                   AS "%OA",

    -- 4. Total Dropsize (Carton Qty / OA)
    ROUND(
        SUM(pcode_qty_carton)::numeric 
        / NULLIF(COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END), 0), 
        2
    )                                                                   AS "Total Dropsize",

    -- 5–10. Deduplicated Repeat Order Buckets
    COUNT(DISTINCT CASE WHEN pcode_order_count = 1  THEN cust_id END)   AS "Non Repeat",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 2  THEN cust_id END)   AS "T2",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 3  THEN cust_id END)   AS "T3",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 4  THEN cust_id END)   AS "T4",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 5  THEN cust_id END)   AS "T5",
    COUNT(DISTINCT CASE WHEN pcode_order_count >= 6 THEN cust_id END)   AS "T6",

    -- 11. % Repeat = ((T2 + T3 + T4 + T5 + T6) / OA) * 100
    ROUND(
        (COUNT(DISTINCT CASE WHEN pcode_order_count >= 2 THEN cust_id END)::numeric 
         / NULLIF(COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END), 0)) * 100, 
        2
    )                                                                   AS "%Repeat"

FROM outlet_orders
GROUP BY ss_id, distributor_id, gsalesforce2_id, gsalesforce2_nm
ORDER BY ss_id, distributor_id, gsalesforce2_id;
