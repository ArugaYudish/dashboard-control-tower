-- NPL Outlet Weekly Omset
-- Output: Distributor | Outlet | Group Channel | Channel | Week | Omset
-- Source: gold_npl_outlet_detail_dev

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

    week                                            AS "Week",

    SUM(
        CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN inv_val ELSE 0
        END
    )                                               AS "Omset"

FROM gold_npl_outlet_detail_dev
WHERE 1=1
  AND is_transaction = 1        -- only transacting rows carry real omset
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
    group_channel_id, group_channel_nm,
    week
ORDER BY distributor_id, cust_id, week;
