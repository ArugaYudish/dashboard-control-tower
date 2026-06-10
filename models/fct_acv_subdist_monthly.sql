{{ config(materialized='table') }}

WITH omset_weekly AS (
    SELECT 
        "year",
        week,
        pcode,
        distributor_id,
        qty AS omset_qty
    FROM spx.v_omset_subdist_weekly
),

calendar_cycle AS (
    SELECT DISTINCT
        "year",
        week,
        period
    FROM spx.m_cycle3
),

omset_monthly AS (
    SELECT 
        o."year",
        c.period,
        o.pcode,
        o.distributor_id,
        SUM(o.omset_qty) AS total_omset_qty
    FROM omset_weekly o
    JOIN calendar_cycle c ON o.week = c.week AND o."year" = c."year"
    GROUP BY o."year", c.period, o.pcode, o.distributor_id
),

target_monthly AS (
    SELECT 
        "year",
        period,
        pcode,
        distributor_id,
        qty AS target_qty
    FROM spx.v_target_subdist_monthly
)

SELECT
    COALESCE(o."year", t."year") AS "year",
    COALESCE(o.period, t.period) AS period,
    COALESCE(o.pcode, t.pcode) AS pcode,
    COALESCE(o.distributor_id, t.distributor_id) AS distributor_id,
    COALESCE(o.total_omset_qty, 0) AS total_omset_qty,
    COALESCE(t.target_qty, 0) AS target_qty,
    
    CASE 
        WHEN COALESCE(t.target_qty, 0) = 0 THEN 0
        ELSE COALESCE(o.total_omset_qty, 0) / t.target_qty
    END AS acv_ratio
FROM omset_monthly o
FULL OUTER JOIN target_monthly t 
    ON o."year" = t."year" 
    AND o.period = t.period 
    AND o.pcode = t.pcode 
    AND o.distributor_id = t.distributor_id
