-- Metabase SQL Query: NPL Combined Breakdown Summary (view_by / break_by switcher)
-- Source: bift.gold_npl_by_*_dev
-- Output: SD | NSM | GRSM | RSM | SS | Distributor | Break By | CB Cover | OA | %OA | Total Dropsize | Non Repeat | T2 | T3 | T4 | T5 | T6 | %Repeat

WITH outlet_orders AS (

    -- ─────────────────────────────────────────────────────
    --  VIEW BY: Group Salesforce 1
    -- ─────────────────────────────────────────────────────
    SELECT
        sd_id, sd_nm,
        nsm_id, nsm_nm,
        grsm_id, grsm_nm,
        rsm_id, rsm_nm,
        ss_id, ss_nm,
        distributor_id, distributor_nm,
        cust_id,
        gsalesforce1_id                                                 AS break_id,
        gsalesforce1_nm                                                 AS break_nm,
        'gsalesforce1'                                                  AS break_by_key,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN order_count ELSE 0 END)                                AS pcode_order_count,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN qty_carton  ELSE 0 END)                                AS pcode_qty_carton
    FROM gold_npl_by_gsalesforce1_dev
    WHERE {{break_by}} = 'gsalesforce1'
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
    GROUP BY
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm,
        ss_id, ss_nm, distributor_id, distributor_nm, cust_id,
        gsalesforce1_id, gsalesforce1_nm

    UNION ALL

    -- ─────────────────────────────────────────────────────
    --  VIEW BY: Group Salesforce 2
    -- ─────────────────────────────────────────────────────
    SELECT
        sd_id, sd_nm,
        nsm_id, nsm_nm,
        grsm_id, grsm_nm,
        rsm_id, rsm_nm,
        ss_id, ss_nm,
        distributor_id, distributor_nm,
        cust_id,
        gsalesforce2_id                                                 AS break_id,
        gsalesforce2_nm                                                 AS break_nm,
        'gsalesforce2'                                                  AS break_by_key,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN order_count ELSE 0 END)                                AS pcode_order_count,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN qty_carton  ELSE 0 END)                                AS pcode_qty_carton
    FROM gold_npl_by_gsalesforce2_dev
    WHERE {{break_by}} = 'gsalesforce2'
      [[ AND {{tahun}} ]]
      [[ AND {{periodes}} ]]
      [[ AND {{weeks}} ]]
      [[ AND {{sd_ids}} ]]
      [[ AND {{nsm_ids}} ]]
      [[ AND {{grsm_ids}} ]]
      [[ AND {{rsm_ids}} ]]
      [[ AND {{ss_ids}} ]]
      [[ AND {{distributor_ids}} ]]
      [[ AND {{gsalesforce2_ids}} ]]
    GROUP BY
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm,
        ss_id, ss_nm, distributor_id, distributor_nm, cust_id,
        gsalesforce2_id, gsalesforce2_nm

    UNION ALL

    -- ─────────────────────────────────────────────────────
    --  VIEW BY: Salesforce
    -- ─────────────────────────────────────────────────────
    SELECT
        sd_id, sd_nm,
        nsm_id, nsm_nm,
        grsm_id, grsm_nm,
        rsm_id, rsm_nm,
        ss_id, ss_nm,
        distributor_id, distributor_nm,
        cust_id,
        salesforce_id                                                   AS break_id,
        salesforce_nm                                                   AS break_nm,
        'salesforce'                                                    AS break_by_key,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN order_count ELSE 0 END)                                AS pcode_order_count,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN qty_carton  ELSE 0 END)                                AS pcode_qty_carton
    FROM gold_npl_by_salesforce_dev
    WHERE {{break_by}} = 'salesforce'
      [[ AND {{tahun}} ]]
      [[ AND {{periodes}} ]]
      [[ AND {{weeks}} ]]
      [[ AND {{sd_ids}} ]]
      [[ AND {{nsm_ids}} ]]
      [[ AND {{grsm_ids}} ]]
      [[ AND {{rsm_ids}} ]]
      [[ AND {{ss_ids}} ]]
      [[ AND {{distributor_ids}} ]]
      [[ AND {{salesforce_ids}} ]]
    GROUP BY
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm,
        ss_id, ss_nm, distributor_id, distributor_nm, cust_id,
        salesforce_id, salesforce_nm

    UNION ALL

    -- ─────────────────────────────────────────────────────
    --  VIEW BY: Group Channel
    -- ─────────────────────────────────────────────────────
    SELECT
        sd_id, sd_nm,
        nsm_id, nsm_nm,
        grsm_id, grsm_nm,
        rsm_id, rsm_nm,
        ss_id, ss_nm,
        distributor_id, distributor_nm,
        cust_id,
        group_channel_id                                                AS break_id,
        group_channel_nm                                                AS break_nm,
        'group_channel'                                                 AS break_by_key,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN order_count ELSE 0 END)                                AS pcode_order_count,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN qty_carton  ELSE 0 END)                                AS pcode_qty_carton
    FROM gold_npl_by_group_channel_dev
    WHERE {{break_by}} = 'group_channel'
      [[ AND {{tahun}} ]]
      [[ AND {{periodes}} ]]
      [[ AND {{weeks}} ]]
      [[ AND {{sd_ids}} ]]
      [[ AND {{nsm_ids}} ]]
      [[ AND {{grsm_ids}} ]]
      [[ AND {{rsm_ids}} ]]
      [[ AND {{ss_ids}} ]]
      [[ AND {{distributor_ids}} ]]
      [[ AND {{group_channel_ids}} ]]
    GROUP BY
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm,
        ss_id, ss_nm, distributor_id, distributor_nm, cust_id,
        group_channel_id, group_channel_nm

    UNION ALL

    -- ─────────────────────────────────────────────────────
    --  VIEW BY: Channel
    -- ─────────────────────────────────────────────────────
    SELECT
        sd_id, sd_nm,
        nsm_id, nsm_nm,
        grsm_id, grsm_nm,
        rsm_id, rsm_nm,
        ss_id, ss_nm,
        distributor_id, distributor_nm,
        cust_id,
        channel_id                                                      AS break_id,
        channel_nm                                                      AS break_nm,
        'channel'                                                       AS break_by_key,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN order_count ELSE 0 END)                                AS pcode_order_count,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN qty_carton  ELSE 0 END)                                AS pcode_qty_carton
    FROM gold_npl_by_channel_dev
    WHERE {{break_by}} = 'channel'
      [[ AND {{tahun}} ]]
      [[ AND {{periodes}} ]]
      [[ AND {{weeks}} ]]
      [[ AND {{sd_ids}} ]]
      [[ AND {{nsm_ids}} ]]
      [[ AND {{grsm_ids}} ]]
      [[ AND {{rsm_ids}} ]]
      [[ AND {{ss_ids}} ]]
      [[ AND {{distributor_ids}} ]]
      [[ AND {{channel_ids}} ]]
    GROUP BY
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm,
        ss_id, ss_nm, distributor_id, distributor_nm, cust_id,
        channel_id, channel_nm

    UNION ALL

    -- ─────────────────────────────────────────────────────
    --  VIEW BY: Salesman
    -- ─────────────────────────────────────────────────────
    SELECT
        sd_id, sd_nm,
        nsm_id, nsm_nm,
        grsm_id, grsm_nm,
        rsm_id, rsm_nm,
        ss_id, ss_nm,
        distributor_id, distributor_nm,
        cust_id,
        sls_id                                                          AS break_id,
        sls_nm                                                          AS break_nm,
        'salesman'                                                      AS break_by_key,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN order_count ELSE 0 END)                                AS pcode_order_count,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN qty_carton  ELSE 0 END)                                AS pcode_qty_carton
    FROM gold_npl_by_salesman_dev
    WHERE {{break_by}} = 'salesman'
      [[ AND {{tahun}} ]]
      [[ AND {{periodes}} ]]
      [[ AND {{weeks}} ]]
      [[ AND {{sd_ids}} ]]
      [[ AND {{nsm_ids}} ]]
      [[ AND {{grsm_ids}} ]]
      [[ AND {{rsm_ids}} ]]
      [[ AND {{ss_ids}} ]]
      [[ AND {{distributor_ids}} ]]
      [[ AND {{sls_ids}} ]]
    GROUP BY
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm,
        ss_id, ss_nm, distributor_id, distributor_nm, cust_id,
        sls_id, sls_nm

    UNION ALL

    -- ─────────────────────────────────────────────────────
    --  VIEW BY: Classification
    -- ─────────────────────────────────────────────────────
    SELECT
        sd_id, sd_nm,
        nsm_id, nsm_nm,
        grsm_id, grsm_nm,
        rsm_id, rsm_nm,
        ss_id, ss_nm,
        distributor_id, distributor_nm,
        cust_id,
        classification_id                                               AS break_id,
        classification_nm                                               AS break_nm,
        'classification'                                                AS break_by_key,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN order_count ELSE 0 END)                                AS pcode_order_count,
        SUM(CASE WHEN 1=1
            [[ AND {{pcodes}} ]]
            [[ AND {{subbrands}} ]]
            THEN qty_carton  ELSE 0 END)                                AS pcode_qty_carton
    FROM gold_npl_by_classification_dev
    WHERE {{break_by}} = 'classification'
      [[ AND {{tahun}} ]]
      [[ AND {{periodes}} ]]
      [[ AND {{weeks}} ]]
      [[ AND {{sd_ids}} ]]
      [[ AND {{nsm_ids}} ]]
      [[ AND {{grsm_ids}} ]]
      [[ AND {{rsm_ids}} ]]
      [[ AND {{ss_ids}} ]]
      [[ AND {{distributor_ids}} ]]
      [[ AND {{classification_ids}} ]]
    GROUP BY
        sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm,
        ss_id, ss_nm, distributor_id, distributor_nm, cust_id,
        classification_id, classification_nm

)

SELECT
    -- Sales Hierarchy
    CASE WHEN sd_id          IS NOT NULL THEN CONCAT(sd_id,          ' - ', sd_nm)          ELSE NULL END AS "SD",
    CASE WHEN nsm_id         IS NOT NULL THEN CONCAT(nsm_id,         ' - ', nsm_nm)         ELSE NULL END AS "NSM",
    CASE WHEN grsm_id        IS NOT NULL THEN CONCAT(grsm_id,        ' - ', grsm_nm)        ELSE NULL END AS "GRSM",
    CASE WHEN rsm_id         IS NOT NULL THEN CONCAT(rsm_id,         ' - ', rsm_nm)         ELSE NULL END AS "RSM",
    CASE WHEN ss_id          IS NOT NULL THEN CONCAT(ss_id,          ' - ', ss_nm)          ELSE NULL END AS "SS",
    CASE WHEN distributor_id IS NOT NULL THEN CONCAT(distributor_id, ' - ', distributor_nm) ELSE NULL END AS "Distributor",

    -- Break By (unified column, value depends on break_by)
    CASE WHEN break_id IS NOT NULL THEN CONCAT(break_id, ' - ', break_nm) ELSE NULL END                       AS "Break By",

    -- Metrics
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

FROM outlet_orders
GROUP BY
    sd_id, sd_nm, nsm_id, nsm_nm, grsm_id, grsm_nm, rsm_id, rsm_nm,
    ss_id, ss_nm, distributor_id, distributor_nm, break_id, break_nm
ORDER BY ss_id, distributor_id, break_id;
