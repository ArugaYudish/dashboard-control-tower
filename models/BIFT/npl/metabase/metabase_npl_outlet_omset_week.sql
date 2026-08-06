SELECT
    nullIf(distributor_nm, '')                      AS "Distributor",
    nullIf(cust_nm, '')                             AS "Outlet",
    nullIf(channel_nm, '')                          AS "Channel",

    week                                            AS "Week",

    sum(
        CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN inv_val ELSE 0
        END
    )                                               AS "Omset"

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
    distributor_nm, cust_nm, channel_nm, week
ORDER BY
    distributor_nm, cust_nm, week;
