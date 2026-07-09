{{ config(materialized='view') }}

SELECT
    year::int   AS year,
    period::int AS period,
    ROW_NUMBER() OVER (ORDER BY year::int, period::int) AS seq
FROM (
    SELECT DISTINCT year, period
    FROM {{ source('spx', 'm_cycle3') }}
) d