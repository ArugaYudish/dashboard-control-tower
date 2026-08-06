WITH outlet_stats AS (
    SELECT
        nullIf(distributor_nm, '')     AS "Distributor",
        nullIf(cust_nm, '')            AS "Outlet",
        nullIf(channel_nm, '')         AS "Channel",
        cust_id,

        sum(
            CASE WHEN 1=1
                [[ AND {{pcodes}} ]]
                [[ AND {{subbrands}} ]]
                THEN order_count ELSE 0
            END
        )                              AS total_order_count,

        sum(
            CASE WHEN 1=1
                [[ AND {{pcodes}} ]]
                [[ AND {{subbrands}} ]]
                THEN qty_carton ELSE 0
            END
        )                              AS total_qty_carton,

        max(is_transaction)            AS is_tx

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
        "Distributor", "Outlet", "Channel", cust_id
)

SELECT
    "Distributor",
    "Outlet",
    "Channel",

    round(total_qty_carton, 2)                     AS "Total Dropsize",

    CASE WHEN total_order_count = 1  THEN 1 ELSE 0 END AS "Non Repeat",
    CASE WHEN total_order_count = 2  THEN 1 ELSE 0 END AS "T2",
    CASE WHEN total_order_count = 3  THEN 1 ELSE 0 END AS "T3",
    CASE WHEN total_order_count = 4  THEN 1 ELSE 0 END AS "T4",
    CASE WHEN total_order_count = 5  THEN 1 ELSE 0 END AS "T5",
    CASE WHEN total_order_count >= 6 THEN 1 ELSE 0 END AS "T6",

    CASE WHEN is_tx = 1 THEN 'Transaction'
         ELSE 'Non Transaction'
    END                                             AS "Status"

FROM outlet_stats
ORDER BY "Distributor", "Outlet";
