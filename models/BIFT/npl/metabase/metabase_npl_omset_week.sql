SELECT
    nullIf(sd_nm, '')              AS "SD",
    nullIf(nsm_nm, '')             AS "NSM",
    nullIf(grsm_nm, '')            AS "GRSM",
    nullIf(rsm_nm, '')             AS "RSM",
    nullIf(ss_nm, '')              AS "SS",
    nullIf(distributor_nm, '')     AS "Distributor",

    CASE
        WHEN {{break_by}} = 'gsalesforce1'   THEN nullIf(gsalesforce1_nm, '')
        WHEN {{break_by}} = 'gsalesforce2'   THEN nullIf(gsalesforce2_nm, '')
        WHEN {{break_by}} = 'salesforce'     THEN nullIf(salesforce_nm, '')
        WHEN {{break_by}} = 'group_channel'  THEN nullIf(group_channel_nm, '')
        WHEN {{break_by}} = 'channel'        THEN nullIf(channel_nm, '')
        WHEN {{break_by}} = 'salesman'       THEN nullIf(sls_nm, '')
        WHEN {{break_by}} = 'classification' THEN nullIf(classification_nm, '')
    END                            AS "Break By",

    week                           AS "Week",

    sum(
        CASE
            WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN inv_val ELSE 0
        END
    )                              AS "Omset"

FROM default.gold_npl_outlet_detail
WHERE is_transaction = 1
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
    "SD", "NSM", "GRSM", "RSM", "SS", "Distributor", "Break By", week
HAVING "Break By" IS NOT NULL AND "Break By" != ''
ORDER BY "SS", "Distributor", "Break By", week;
