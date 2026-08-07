WITH outlet_orders AS (
    SELECT
        concat(distributor_id, '_', cust_id) AS dist_cust_key,

        CASE
            WHEN {{summaryBy}} = 'gsalesforce1'   THEN nullIf(gsalesforce1_nm, '')
            WHEN {{summaryBy}} = 'gsalesforce2'   THEN nullIf(gsalesforce2_nm, '')
            WHEN {{summaryBy}} = 'salesforce'     THEN nullIf(salesforce_nm, '')
            WHEN {{summaryBy}} = 'group_channel'  THEN nullIf(group_channel_nm, '')
            WHEN {{summaryBy}} = 'channel'        THEN nullIf(channel_nm, '')
            WHEN {{summaryBy}} = 'salesman'       THEN nullIf(sls_nm, '')
            WHEN {{summaryBy}} = 'classification' THEN nullIf(classification_nm, '')
        END                                                                 AS "Summary By",

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

    GROUP BY
        dist_cust_key, "Summary By"
),

bucket_summary AS (
    SELECT
        "Summary By",
        uniqExactIf(dist_cust_key, pcode_order_count = 1)                          AS t1,
        uniqExactIf(dist_cust_key, pcode_order_count = 2)                          AS t2,
        uniqExactIf(dist_cust_key, pcode_order_count = 3)                          AS t3,
        uniqExactIf(dist_cust_key, pcode_order_count = 4)                          AS t4,
        uniqExactIf(dist_cust_key, pcode_order_count = 5)                          AS t5,
        uniqExactIf(dist_cust_key, pcode_order_count >= 6)                         AS t6
    FROM outlet_orders
    WHERE "Summary By" IS NOT NULL AND "Summary By" != ''
    GROUP BY "Summary By"
)

SELECT
    "Summary By",
    bucket.1 AS bucket_order,
    bucket.2 AS "Repeat Bucket",
    bucket.3 AS "Outlet Count"
FROM bucket_summary
ARRAY JOIN [
    (1, 'T1', t1),
    (2, 'T2', t2),
    (3, 'T3', t3),
    (4, 'T4', t4),
    (5, 'T5', t5),
    (6, 'T6', t6)
] AS bucket
ORDER BY "Summary By", bucket_order;
