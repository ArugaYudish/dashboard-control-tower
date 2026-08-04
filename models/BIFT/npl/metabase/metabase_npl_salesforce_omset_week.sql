-- Metabase SQL Query: NPL Breakdown Weekly Omset by Salesforce
-- Source: bift.gold_npl_by_salesforce_dev (or bift.gold_npl_by_salesforce in production)
-- Output: SD | NSM | GRSM | RSM | SS | Distributor | Break By (salesforce_id - salesforce_nm) | week | omset

WITH outlet_orders AS (
    SELECT
        ss_id,
        distributor_id,
        salesforce_id,
        salesforce_nm,
        week,

        -- Omset for selected pcodes/subbrands in the selected week range
        SUM(
            CASE 
                WHEN 1=1
                [[ AND pcode IN ({{pcodes}}) ]]
                [[ AND subbrand_id IN ({{subbrands}}) ]]
                THEN inv_val 
                ELSE 0 
            END
        )                                                               AS week_omset,

        -- Retrieve parent sales hierarchy attributes (Zero CPU overhead via MAX)
        MAX(ss_nm)                                                      AS ss_nm,
        MAX(rsm_id)                                                     AS rsm_id,
        MAX(rsm_nm)                                                     AS rsm_nm,
        MAX(grsm_id)                                                    AS grsm_id,
        MAX(grsm_nm)                                                    AS grsm_nm,
        MAX(nsm_id)                                                     AS nsm_id,
        MAX(nsm_nm)                                                     AS nsm_nm,
        MAX(sd_id)                                                      AS sd_id,
        MAX(sd_nm)                                                      AS sd_nm,
        MAX(distributor_nm)                                             AS distributor_nm

    FROM bift.gold_npl_by_salesforce_dev
    WHERE 1=1
      [[ AND tahun = {{tahun}}::numeric ]]
      [[ AND week BETWEEN COALESCE(NULLIF('{{weekFrom}}', ''), '1')::numeric AND COALESCE(NULLIF('{{weekTo}}', ''), '53')::numeric ]]
      [[ AND distributor_id IN ({{distributor_ids}}) ]]
      [[ AND rsm_id IN ({{rsm_ids}}) ]]
      [[ AND ss_id IN ({{ss_ids}}) ]]
      [[ AND salesforce_id IN ({{salesforce_ids}}) ]]

    GROUP BY ss_id, distributor_id, salesforce_id, salesforce_nm, week
)

SELECT
    -- Concatenated Sales Hierarchy Output
    CASE WHEN MAX(sd_id) IS NOT NULL THEN CONCAT(MAX(sd_id), ' - ', MAX(sd_nm)) ELSE NULL END                      AS "SD",
    CASE WHEN MAX(nsm_id) IS NOT NULL THEN CONCAT(MAX(nsm_id), ' - ', MAX(nsm_nm)) ELSE NULL END                  AS "NSM",
    CASE WHEN MAX(grsm_id) IS NOT NULL THEN CONCAT(MAX(grsm_id), ' - ', MAX(grsm_nm)) ELSE NULL END               AS "GRSM",
    CASE WHEN MAX(rsm_id) IS NOT NULL THEN CONCAT(MAX(rsm_id), ' - ', MAX(rsm_nm)) ELSE NULL END                  AS "RSM",
    CASE WHEN ss_id IS NOT NULL THEN CONCAT(ss_id, ' - ', MAX(ss_nm)) ELSE NULL END                                AS "SS",
    CASE WHEN distributor_id IS NOT NULL THEN CONCAT(distributor_id, ' - ', MAX(distributor_nm)) ELSE NULL END    AS "Distributor",

    -- Break By Column (salesforce_id - salesforce_nm)
    CASE 
        WHEN salesforce_id IS NOT NULL 
        THEN CONCAT(salesforce_id, ' - ', salesforce_nm)
        ELSE NULL 
    END                                                                 AS break_by_salesforce,
    week,

    -- Weekly Omset
    SUM(week_omset)                                                     AS omset

FROM outlet_orders
GROUP BY ss_id, distributor_id, salesforce_id, salesforce_nm, week
ORDER BY ss_id, distributor_id, salesforce_id, week;
