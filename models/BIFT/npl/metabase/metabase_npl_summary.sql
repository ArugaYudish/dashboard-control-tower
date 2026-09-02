WITH outlet_orders AS (
    SELECT
        concat(distributor_id, '_', cust_id) AS dist_cust_key,

        CASE
            WHEN {{view_by}} = 'sd'          THEN nullIf(sd_nm, '')
            WHEN {{view_by}} = 'nsm'         THEN nullIf(nsm_nm, '')
            WHEN {{view_by}} = 'grsm'        THEN nullIf(grsm_nm, '')
            WHEN {{view_by}} = 'rsm'         THEN nullIf(rsm_nm, '')
            WHEN {{view_by}} = 'ss'          THEN nullIf(ss_nm, '')
            WHEN {{view_by}} = 'distributor' THEN nullIf(distributor_nm, '')
        END                                                                 AS "View By",

        max(CASE WHEN is_transaction = 0 THEN 1 ELSE 0 END)                AS is_cb_cover,

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
        )                                                                   AS pcode_qty_carton,

        sum(
            CASE
                WHEN 1=1
                [[ AND {{pcodes}} ]]
                [[ AND {{subbrands}} ]]
                THEN inv_val ELSE 0
            END
        )                                                                   AS pcode_inv_val

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
      AND (
          (is_transaction = 0 AND (tahun, periode) IN (
              SELECT toUInt16(year), toUInt8(period)
              FROM default.m_cycle3
              WHERE (toUInt16(year), toUInt8(period)) IN (
                  SELECT DISTINCT tahun, periode FROM default.gold_npl_outlet_detail_dev
              )
              [[ AND {{date}} ]]
              ORDER BY toUInt16(year) DESC, toUInt8(period) DESC
              LIMIT 1
          ))
          OR
          (is_transaction = 1 AND (tahun, periode, week) IN (
              SELECT DISTINCT toUInt16(year), toUInt8(period), toUInt8(week)
              FROM default.m_cycle3
              WHERE (toUInt16(year), toUInt8(period)) IN (
                  SELECT DISTINCT tahun, periode FROM default.gold_npl_outlet_detail_dev
              )
              [[ AND {{date}} ]]
          ))
      )

    GROUP BY
        dist_cust_key, "View By"
)

SELECT
    "View By",

    uniqExactIf(dist_cust_key, is_cb_cover = 1)                                    AS "CB Cover",
    uniqExactIf(dist_cust_key, pcode_order_count >= 1)                             AS "OA",
    round(
        (uniqExactIf(dist_cust_key, pcode_order_count >= 1) / nullIf(uniqExactIf(dist_cust_key, is_cb_cover = 1), 0)) * 100, 2
    )                                                                               AS "%OA",
    round(
        CASE
            WHEN {{dropsize_by}} = 'inv_val'
            THEN sum(pcode_inv_val) / nullIf(sum(pcode_order_count), 0)
            ELSE sum(pcode_qty_carton) / nullIf(sum(pcode_order_count), 0)
        END, 2
    )                                                                               AS "Total Dropsize",

    uniqExactIf(dist_cust_key, pcode_order_count = 1)                              AS "Non Repeat",
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
