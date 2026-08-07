WITH outlet_orders AS (
    SELECT
        nullIf(sd_nm, '')              AS "SD",
        nullIf(nsm_nm, '')             AS "NSM",
        nullIf(grsm_nm, '')            AS "GRSM",
        nullIf(rsm_nm, '')             AS "RSM",
        nullIf(ss_nm, '')              AS "SS",
        nullIf(distributor_nm, '')     AS "Distributor",
        concat(distributor_id, '_', cust_id) AS dist_cust_key,

        CASE
            WHEN {{break_by}} = 'gsalesforce1'   THEN nullIf(gsalesforce1_nm, '')
            WHEN {{break_by}} = 'gsalesforce2'   THEN nullIf(gsalesforce2_nm, '')
            WHEN {{break_by}} = 'salesforce'     THEN nullIf(salesforce_nm, '')
            WHEN {{break_by}} = 'group_channel'  THEN nullIf(group_channel_nm, '')
            WHEN {{break_by}} = 'channel'        THEN nullIf(channel_nm, '')
            WHEN {{break_by}} = 'salesman'       THEN nullIf(sls_nm, '')
            WHEN {{break_by}} = 'classification' THEN nullIf(classification_nm, '')
        END                                                                 AS "Break By",

        sum(
            CASE
                WHEN 1=1
                [[ AND {{pcodes}} ]]
                [[ AND {{subbrands}} ]]
                THEN order_count ELSE 0
            END
        )                                                                   AS pcode_order_count,

        sum(
            CASE
                WHEN 1=1
                [[ AND {{pcodes}} ]]
                [[ AND {{subbrands}} ]]
                THEN qty_carton ELSE 0
            END
        )                                                                   AS pcode_qty_carton

    FROM default.gold_npl_outlet_detail
    WHERE 1=1
      [[ AND {{tahun}} ]]
      [[ AND {{periodes}} ]]
      [[ AND {{weeks}} ]]
      [[ AND {{sd_ids}} ]]
      [[ AND {{nsm_ids}} ]]
      [[ AND {{grsm_ids}} ]]
      [[ AND {{rsm_ids}} ]]
      [[ AND {{ss_ids}} ]]
      [[ AND {{distributor_ids}} ]]
      [[ AND {{gsalesforce1_ids}} ]]
      [[ AND {{gsalesforce2_ids}} ]]
      [[ AND {{salesforce_ids}} ]]
      [[ AND {{group_channel_ids}} ]]
      [[ AND {{channel_ids}} ]]
      [[ AND {{sls_ids}} ]]
      [[ AND {{classification_ids}} ]]
      [[ AND {{app_url}} = {{app_url}} ]]

    GROUP BY
        "SD", "NSM", "GRSM", "RSM", "SS", "Distributor", dist_cust_key, "Break By"
)

SELECT
    "SD", "NSM", "GRSM", "RSM", "SS", "Distributor", "Break By",

    uniqExact(dist_cust_key)                                                        AS "CB Cover",
    uniqExactIf(dist_cust_key, pcode_order_count >= 1)                             AS "OA",
    round(
        (uniqExactIf(dist_cust_key, pcode_order_count >= 1) / nullIf(uniqExact(dist_cust_key), 0)) * 100, 2
    )                                                                               AS "%OA",
    round(
        sum(pcode_qty_carton) / nullIf(sum(pcode_order_count), 0), 2
    )                                                                               AS "Total Dropsize",

    uniqExactIf(dist_cust_key, pcode_order_count = 1)                              AS "Non Repeat",
    uniqExactIf(dist_cust_key, pcode_order_count = 2)                              AS "T2",
    uniqExactIf(dist_cust_key, pcode_order_count = 3)                              AS "T3",
    uniqExactIf(dist_cust_key, pcode_order_count = 4)                              AS "T4",
    uniqExactIf(dist_cust_key, pcode_order_count = 5)                              AS "T5",
    uniqExactIf(dist_cust_key, pcode_order_count >= 6)                             AS "T6",

    round(
        (uniqExactIf(dist_cust_key, pcode_order_count >= 2) / nullIf(uniqExactIf(dist_cust_key, pcode_order_count >= 1), 0)) * 100, 2
    )                                                                               AS "%Repeat",
    toString({{app_url}})                                                           AS "app_url"

FROM outlet_orders
WHERE "Break By" IS NOT NULL AND "Break By" != ''
GROUP BY "SD", "NSM", "GRSM", "RSM", "SS", "Distributor", "Break By"
ORDER BY "SS", "Distributor", "Break By";
