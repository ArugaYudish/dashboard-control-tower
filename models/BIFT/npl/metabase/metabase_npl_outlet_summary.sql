-- NPL Outlet-Level Summary
-- Output: Distributor | Outlet | Group Channel | Channel | Total Dropsize | Order Count | Bucket | Status
-- Source: gold_npl_outlet_detail_dev

WITH outlet_stats AS (
    SELECT
        distributor_id,
        distributor_nm,
        cust_id,
        cust_nm,
        channel_id,
        channel_nm,
        group_channel_id,
        group_channel_nm,

        -- Total order count across the full period (all pcodes × weeks)
        SUM(
            CASE WHEN 1=1
                [[ AND {{pcodes}} ]]
                [[ AND {{subbrands}} ]]
                THEN order_count ELSE 0
            END
        )                                   AS total_order_count,

        -- Total qty carton (for dropsize)
        SUM(
            CASE WHEN 1=1
                [[ AND {{pcodes}} ]]
                [[ AND {{subbrands}} ]]
                THEN qty_carton ELSE 0
            END
        )                                   AS total_qty_carton,

        -- 1 if this outlet ever transacted in the period, 0 if never
        MAX(is_transaction)                 AS is_transaction

    FROM gold_npl_outlet_detail_dev
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
        distributor_id, distributor_nm,
        cust_id, cust_nm,
        channel_id, channel_nm,
        group_channel_id, group_channel_nm
)

SELECT
    CASE WHEN distributor_id IS NOT NULL
         THEN CONCAT(distributor_id, ' - ', distributor_nm)
         ELSE NULL END                              AS "Distributor",
    CASE WHEN cust_id IS NOT NULL
         THEN CONCAT(cust_id, ' - ', cust_nm)
         ELSE NULL END                              AS "Outlet",
    CASE WHEN group_channel_id IS NOT NULL
         THEN CONCAT(group_channel_id, ' - ', group_channel_nm)
         ELSE NULL END                              AS "Group Channel",
    CASE WHEN channel_id IS NOT NULL
         THEN CONCAT(channel_id, ' - ', channel_nm)
         ELSE NULL END                              AS "Channel",

    ROUND(total_qty_carton::numeric, 2)             AS "Total Dropsize",

    CASE
        WHEN total_order_count = 0  THEN 'No Transaction'
        WHEN total_order_count = 1  THEN 'Non Repeat'
        WHEN total_order_count = 2  THEN 'T2'
        WHEN total_order_count = 3  THEN 'T3'
        WHEN total_order_count = 4  THEN 'T4'
        WHEN total_order_count = 5  THEN 'T5'
        WHEN total_order_count >= 6 THEN 'T6'
    END                                             AS "Bucket",

    total_order_count                               AS "Order Count",

    CASE WHEN is_transaction = 1 THEN 'Transaction'
         ELSE 'No Transaction'
    END                                             AS "Status"

FROM outlet_stats
ORDER BY distributor_id, cust_id;
