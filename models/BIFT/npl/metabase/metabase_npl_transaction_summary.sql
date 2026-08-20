WITH outlet_stats AS (
    SELECT
        nullIf(distributor_nm, '')     AS "Distributor",
        nullIf(cust_nm, '')            AS "Outlet",
        nullIf(sls_nm, '')             AS "Salesman",
        nullIf(channel_nm, '')         AS "Channel",
        concat(distributor_id, '_', sls_id, '_', cust_id) AS dist_sls_cust_key,

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

        sum(
            CASE WHEN 1=1
                [[ AND {{pcodes}} ]]
                [[ AND {{subbrands}} ]]
                THEN inv_val ELSE 0
            END
        )                              AS total_inv_val,

        max(is_transaction)            AS is_tx

    FROM default.gold_npl_outlet_detail_dev
    WHERE 1=1
      [[ AND {{gdiv_ids}} ]]
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
      AND (
          (is_transaction = 0 AND (tahun, periode) IN (
              SELECT DISTINCT toUInt16(year), toUInt8(period)
              FROM default.m_cycle3
              WHERE 1=1 [[ AND {{date}} ]]
          ))
          OR
          (is_transaction = 1 AND (tahun, periode, week) IN (
              SELECT DISTINCT toUInt16(year), toUInt8(period), toUInt8(week)
              FROM default.m_cycle3
              WHERE 1=1 [[ AND {{date}} ]]
          ))
      )

    GROUP BY
        "Distributor", "Outlet", "Salesman", "Channel", dist_sls_cust_key
)

SELECT
    "Distributor",
    "Outlet",
    "Salesman",
    "Channel",

    round(
        CASE
            WHEN {{dropsize_by}} = 'inv_val' THEN total_inv_val / nullIf(total_order_count, 0)
            ELSE total_qty_carton / nullIf(total_order_count, 0)
        END, 2
    )                                               AS "Total Dropsize",

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
ORDER BY "Distributor", "Outlet", "Salesman";
