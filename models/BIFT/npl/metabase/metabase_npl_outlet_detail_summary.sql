-- Metabase SQL Query: NPL Outlet Detail Summary
-- Source: bift.gold_npl_outlet_detail_dev
-- Output: Distributor | Customer | Channel | CB Cover | OA | %OA | Total Dropsize | Non Repeat | T2-T6 | %Repeat | Status

WITH outlet_orders AS (
    SELECT
        ss_id,
        distributor_id,
        distributor_nm,
        cust_id,
        cust_nm,
        channel_id,
        channel_nm,

        -- Pcode-filtered order count (for repeat bucket calculation)
        SUM(
            CASE
                WHEN 1=1
                [[ AND pcode IN ({{pcodes}}) ]]
                THEN order_count
                ELSE 0
            END
        )                                                               AS pcode_order_count,

        -- Pcode-filtered qty carton (for dropsize)
        SUM(
            CASE
                WHEN 1=1
                [[ AND pcode IN ({{pcodes}}) ]]
                THEN qty_carton
                ELSE 0
            END
        )                                                               AS pcode_qty_carton,

        -- Transaction status: 1 if outlet has ANY transaction this period
        MAX(is_transaction)                                             AS has_transaction

        -- Sales hierarchy for display
        -- MAX(sd_id)                                                      AS sd_id,
        -- MAX(sd_nm)                                                      AS sd_nm,
        -- MAX(nsm_id)                                                     AS nsm_id,
        -- MAX(nsm_nm)                                                     AS nsm_nm,
        -- MAX(grsm_id)                                                    AS grsm_id,
        -- MAX(grsm_nm)                                                    AS grsm_nm,
        -- MAX(rsm_id)                                                     AS rsm_id,
        -- MAX(rsm_nm)                                                     AS rsm_nm,
        -- MAX(ss_nm)                                                      AS ss_nm

    FROM bift.gold_npl_outlet_detail_dev
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
      [[ AND gsalesforce1_id IN ({{gsalesforce1_ids}}) ]]
      [[ AND gsalesforce2_id IN ({{gsalesforce2_ids}}) ]]
      [[ AND salesforce_id IN ({{salesforce_ids}}) ]]
      [[ AND group_channel_id IN ({{group_channel_ids}}) ]]
      [[ AND channel_id IN ({{channel_ids}}) ]]
      [[ AND sls_id IN ({{sls_ids}}) ]]
      [[ AND classification_id IN ({{classification_ids}}) ]]

    GROUP BY ss_id, distributor_id, distributor_nm, cust_id, cust_nm, channel_id, channel_nm
)

SELECT
    -- Sales Hierarchy
    -- CASE WHEN MAX(sd_id) IS NOT NULL THEN CONCAT(MAX(sd_id), ' - ', MAX(sd_nm)) ELSE NULL END                      AS "SD",
    -- CASE WHEN MAX(nsm_id) IS NOT NULL THEN CONCAT(MAX(nsm_id), ' - ', MAX(nsm_nm)) ELSE NULL END                  AS "NSM",
    -- CASE WHEN MAX(grsm_id) IS NOT NULL THEN CONCAT(MAX(grsm_id), ' - ', MAX(grsm_nm)) ELSE NULL END               AS "GRSM",
    -- CASE WHEN MAX(rsm_id) IS NOT NULL THEN CONCAT(MAX(rsm_id), ' - ', MAX(rsm_nm)) ELSE NULL END                  AS "RSM",
    -- CASE WHEN ss_id IS NOT NULL THEN CONCAT(ss_id, ' - ', MAX(ss_nm)) ELSE NULL END                                AS "SS",

    -- Distributor
    CASE WHEN distributor_id IS NOT NULL THEN CONCAT(distributor_id, ' - ', MAX(distributor_nm)) ELSE NULL END     AS "Distributor",

    -- Customer / Outlet
    CASE WHEN cust_id IS NOT NULL THEN CONCAT(cust_id, ' - ', MAX(cust_nm)) ELSE NULL END                          AS "Customer",

    -- Channel
    CASE WHEN channel_id IS NOT NULL THEN CONCAT(channel_id, ' - ', channel_nm) ELSE NULL END                      AS "Channel",

    ROUND(
        SUM(pcode_qty_carton)::numeric
        / NULLIF(COUNT(DISTINCT CASE WHEN pcode_order_count >= 1 THEN cust_id END), 0),
        2
    )                                                                                                               AS "Total Dropsize",

    COUNT(DISTINCT CASE WHEN pcode_order_count = 1  THEN cust_id END)                                              AS "Non Repeat",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 2  THEN cust_id END)                                              AS "T2",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 3  THEN cust_id END)                                              AS "T3",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 4  THEN cust_id END)                                              AS "T4",
    COUNT(DISTINCT CASE WHEN pcode_order_count = 5  THEN cust_id END)                                              AS "T5",
    COUNT(DISTINCT CASE WHEN pcode_order_count >= 6 THEN cust_id END)                                              AS "T6",

    -- Transaction Status
    CASE WHEN MAX(has_transaction) = 1 THEN 'Transaction' ELSE 'No Transaction' END                                AS "Status"

FROM outlet_orders
GROUP BY ss_id, distributor_id, distributor_nm, cust_id, cust_nm, channel_id, channel_nm
ORDER BY distributor_id, cust_id, channel_id;
