
WITH outlet_orders AS (
    SELECT
        sd_id, sd_nm,
        nsm_id, nsm_nm,
        grsm_id, grsm_nm,
        rsm_id, rsm_nm,
        ss_id, ss_nm,
        distributor_id, distributor_nm,
        cust_id,

        CASE
            WHEN {{break_by}} = 'gsalesforce1'   THEN gsalesforce1_id
            WHEN {{break_by}} = 'gsalesforce2'   THEN gsalesforce2_id
            WHEN {{break_by}} = 'salesforce'     THEN salesforce_id
            WHEN {{break_by}} = 'group_channel'  THEN group_channel_id
            WHEN {{break_by}} = 'channel'        THEN channel_id
            WHEN {{break_by}} = 'salesman'       THEN sls_id
            WHEN {{break_by}} = 'classification' THEN classification_id
        END                                                             AS break_id,

        CASE
            WHEN {{break_by}} = 'gsalesforce1'   THEN gsalesforce1_nm
            WHEN {{break_by}} = 'gsalesforce2'   THEN gsalesforce2_nm
            WHEN {{break_by}} = 'salesforce'     THEN salesforce_nm
            WHEN {{break_by}} = 'group_channel'  THEN group_channel_nm
            WHEN {{break_by}} = 'channel'        THEN channel_nm
            WHEN {{break_by}} = 'salesman'       THEN sls_nm
            WHEN {{break_by}} = 'classification' THEN classification_nm
        END                                                             AS break_nm,

        SUM(
            CASE
                WHEN 1=1
                [[ AND {{pcodes}} ]]
                [[ AND {{subbrands}} ]]
                THEN order_count
                ELSE 0
            END
        )                                                               AS pcode_order_count,

        SUM(
            CASE
                WHEN 1=1
                [[ AND {{pcodes}} ]]
                [[ AND {{subbrands}} ]]
                THEN qty_carton
                ELSE 0
            END
        )                                                               AS pcode_qty_carton

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
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm,
        ss_id, ss_nm, distributor_id, distributor_nm, cust_id,
        CASE
            WHEN {{break_by}} = 'gsalesforce1'   THEN gsalesforce1_id
            WHEN {{break_by}} = 'gsalesforce2'   THEN gsalesforce2_id
            WHEN {{break_by}} = 'salesforce'     THEN salesforce_id
            WHEN {{break_by}} = 'group_channel'  THEN group_channel_id
            WHEN {{break_by}} = 'channel'        THEN channel_id
            WHEN {{break_by}} = 'salesman'       THEN sls_id
            WHEN {{break_by}} = 'classification' THEN classification_id
        END,
        CASE
            WHEN {{break_by}} = 'gsalesforce1'   THEN gsalesforce1_nm
            WHEN {{break_by}} = 'gsalesforce2'   THEN gsalesforce2_nm
            WHEN {{break_by}} = 'salesforce'     THEN salesforce_nm
            WHEN {{break_by}} = 'group_channel'  THEN group_channel_nm
            WHEN {{break_by}} = 'channel'        THEN channel_nm
            WHEN {{break_by}} = 'salesman'       THEN sls_nm
            WHEN {{break_by}} = 'classification' THEN classification_nm
        END
),

filtered_orders AS (
    SELECT * FROM outlet_orders WHERE break_id IS NOT NULL
)

SELECT
    CASE WHEN sd_id          IS NOT NULL THEN CONCAT(sd_id,          ' - ', sd_nm)          ELSE NULL END AS "SD",
    CASE WHEN nsm_id         IS NOT NULL THEN CONCAT(nsm_id,         ' - ', nsm_nm)         ELSE NULL END AS "NSM",
    CASE WHEN grsm_id        IS NOT NULL THEN CONCAT(grsm_id,        ' - ', grsm_nm)        ELSE NULL END AS "GRSM",
    CASE WHEN rsm_id         IS NOT NULL THEN CONCAT(rsm_id,         ' - ', rsm_nm)         ELSE NULL END AS "RSM",
    CASE WHEN ss_id          IS NOT NULL THEN CONCAT(ss_id,          ' - ', ss_nm)          ELSE NULL END AS "SS",
    CASE WHEN distributor_id IS NOT NULL THEN CONCAT(distributor_id, ' - ', distributor_nm) ELSE NULL END AS "Distributor",

    CASE WHEN break_id IS NOT NULL THEN CONCAT(break_id, ' - ', break_nm) ELSE NULL END                       AS "Break By",

    COUNT(DISTINCT cust_id)                                                                                    AS "CB Cover",
    COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END)                                         AS "OA",
    ROUND(
        (COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END)::numeric
         / NULLIF(COUNT(DISTINCT cust_id), 0)) * 100, 2
    )                                                                                                          AS "%OA",
    ROUND(
        SUM(pcode_qty_carton)::numeric
        / NULLIF(COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END), 0), 2
    )                                                                                                          AS "Total Dropsize",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 1  THEN cust_id END)                                         AS "Non Repeat",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 2  THEN cust_id END)                                         AS "T2",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 3  THEN cust_id END)                                         AS "T3",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 4  THEN cust_id END)                                         AS "T4",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 5  THEN cust_id END)                                         AS "T5",
    COUNT(DISTINCT CASE WHEN pcode_order_count >= 6 THEN cust_id END)                                         AS "T6",
    ROUND(
        (COUNT(DISTINCT CASE WHEN pcode_order_count >= 2 THEN cust_id END)::numeric
         / NULLIF(COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END), 0)) * 100, 2
    )                                                                                                          AS "%Repeat"

FROM filtered_orders
GROUP BY
    sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm,
    ss_id, ss_nm, distributor_id, distributor_nm, break_id, break_nm
ORDER BY ss_id, distributor_id, break_id;
