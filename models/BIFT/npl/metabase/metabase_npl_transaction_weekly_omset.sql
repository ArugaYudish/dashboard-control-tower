SELECT
    nullIf(distributor_nm, '')                      AS "Distributor",
    nullIf(cust_nm, '')                             AS "Outlet",
    nullIf(sls_nm, '')                              AS "Salesman",
    nullIf(channel_nm, '')                          AS "Channel",

    week                                            AS "Week",

    sum(inv_val)                                    AS "Omset By Val",
    round(sum(qty_carton), 2)                       AS "Omset By Qty"

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
  [[ AND {{pcodes}} ]]
  [[ AND {{subbrands}} ]]

GROUP BY
    distributor_nm, cust_nm, sls_nm, channel_nm, week
ORDER BY
    distributor_nm, cust_nm, sls_nm, week;
