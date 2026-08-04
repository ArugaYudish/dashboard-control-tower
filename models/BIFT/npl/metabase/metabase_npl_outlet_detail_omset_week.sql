-- Metabase SQL Query: NPL Outlet Detail - Weekly Omset
-- Source: bift.gold_npl_outlet_detail_dev
-- Output: Distributor | Customer | Channel | Week | Omset (inv_val)

WITH outlet_orders AS (
    SELECT
        ss_id,
        distributor_id,
        cust_id,
        cust_nm,
        channel_id,
        channel_nm,
        week,

        SUM(inv_val)                                                    AS week_omset,

        MAX(distributor_nm)                                             AS distributor_nm,
        MAX(sd_id)                                                      AS sd_id,
        MAX(sd_nm)                                                      AS sd_nm,
        MAX(nsm_id)                                                     AS nsm_id,
        MAX(nsm_nm)                                                     AS nsm_nm,
        MAX(grsm_id)                                                    AS grsm_id,
        MAX(grsm_nm)                                                    AS grsm_nm,
        MAX(rsm_id)                                                     AS rsm_id,
        MAX(rsm_nm)                                                     AS rsm_nm,
        MAX(ss_nm)                                                      AS ss_nm

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
      [[ AND pcode IN ({{pcodes}}) ]]

    GROUP BY ss_id, distributor_id, cust_id, cust_nm, channel_id, channel_nm, week
)

SELECT
    -- Sales Hierarchy
    CASE WHEN MAX(sd_id) IS NOT NULL THEN CONCAT(MAX(sd_id), ' - ', MAX(sd_nm)) ELSE NULL END                      AS "SD",
    CASE WHEN MAX(nsm_id) IS NOT NULL THEN CONCAT(MAX(nsm_id), ' - ', MAX(nsm_nm)) ELSE NULL END                  AS "NSM",
    CASE WHEN MAX(grsm_id) IS NOT NULL THEN CONCAT(MAX(grsm_id), ' - ', MAX(grsm_nm)) ELSE NULL END               AS "GRSM",
    CASE WHEN MAX(rsm_id) IS NOT NULL THEN CONCAT(MAX(rsm_id), ' - ', MAX(rsm_nm)) ELSE NULL END                  AS "RSM",
    CASE WHEN ss_id IS NOT NULL THEN CONCAT(ss_id, ' - ', MAX(ss_nm)) ELSE NULL END                                AS "SS",

    -- Distributor
    CASE WHEN distributor_id IS NOT NULL THEN CONCAT(distributor_id, ' - ', MAX(distributor_nm)) ELSE NULL END     AS "Distributor",

    -- Customer / Outlet
    CASE WHEN cust_id IS NOT NULL THEN CONCAT(cust_id, ' - ', MAX(cust_nm)) ELSE NULL END                          AS "Customer",

    -- Channel
    CASE WHEN channel_id IS NOT NULL THEN CONCAT(channel_id, ' - ', channel_nm) ELSE NULL END                      AS "Channel",

    week                                                                                                            AS "Week",

    -- Weekly Omset
    SUM(week_omset)                                                                                                 AS "Omset"

FROM outlet_orders
GROUP BY ss_id, distributor_id, cust_id, cust_nm, channel_id, channel_nm, week
ORDER BY distributor_id, cust_id, channel_id, week;
