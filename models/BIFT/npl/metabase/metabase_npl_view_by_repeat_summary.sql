WITH outlet_orders AS (
    SELECT
        concat(distributor_id, '_', cust_id) AS dist_cust_key,

        CASE
            WHEN {{view_by}} = 'sd'             THEN nullIf(sd_nm, '')
            WHEN {{view_by}} = 'nsm'            THEN nullIf(nsm_nm, '')
            WHEN {{view_by}} = 'grsm'           THEN nullIf(grsm_nm, '')
            WHEN {{view_by}} = 'rsm'            THEN nullIf(rsm_nm, '')
            WHEN {{view_by}} = 'ss'             THEN nullIf(ss_nm, '')
            WHEN {{view_by}} = 'distributor'    THEN nullIf(distributor_nm, '')
            WHEN {{view_by}} = 'gsalesforce1'   THEN nullIf(gsalesforce1_nm, '')
            WHEN {{view_by}} = 'gsalesforce2'   THEN nullIf(gsalesforce2_nm, '')
            WHEN {{view_by}} = 'salesforce'     THEN nullIf(salesforce_nm, '')
            WHEN {{view_by}} = 'group_channel'  THEN nullIf(group_channel_nm, '')
            WHEN {{view_by}} = 'channel'        THEN nullIf(channel_nm, '')
            WHEN {{view_by}} = 'salesman'       THEN nullIf(sls_nm, '')
            WHEN {{view_by}} = 'classification' THEN nullIf(classification_nm, '')
        END                                                                 AS "View By",

        sum(
            CASE
                WHEN 1=1
                [[ AND {{pcodes}} ]]
                [[ AND {{subbrands}} ]]
                THEN order_count ELSE 0
            END
        )                                                                   AS pcode_order_count

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
      [[ AND {{cust_ids}} ]]

    GROUP BY
        dist_cust_key, "View By"
)

SELECT
    "View By",

    uniqExact(dist_cust_key)                                                        AS "CB",
    uniqExactIf(dist_cust_key, pcode_order_count >= 1)                             AS "OA",
    round(
        (uniqExactIf(dist_cust_key, pcode_order_count >= 1) / nullIf(uniqExact(dist_cust_key), 0)) * 100, 2
    )                                                                               AS "%OA",

    uniqExactIf(dist_cust_key, pcode_order_count = 1)                              AS "T1",
    uniqExactIf(dist_cust_key, pcode_order_count = 2)                              AS "T2",
    uniqExactIf(dist_cust_key, pcode_order_count = 3)                              AS "T3",
    uniqExactIf(dist_cust_key, pcode_order_count = 4)                              AS "T4",
    uniqExactIf(dist_cust_key, pcode_order_count = 5)                              AS "T5",
    uniqExactIf(dist_cust_key, pcode_order_count >= 6)                             AS "T6",

    round(
        (uniqExactIf(dist_cust_key, pcode_order_count >= 2) / nullIf(uniqExactIf(dist_cust_key, pcode_order_count >= 1), 0)) * 100, 2
    )                                                                               AS "%Repeat"

FROM outlet_orders
WHERE "View By" IS NOT NULL AND "View By" != ''
GROUP BY "View By"
ORDER BY "View By";
