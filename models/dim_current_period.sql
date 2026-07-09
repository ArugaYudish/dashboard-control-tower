{{ config(materialized='view') }}

SELECT
    ps.year,
    ps.period,
    ps.seq
FROM {{ source('spx', 'm_cycle3') }} mc
JOIN {{ ref('dim_period_seq') }} ps
    ON ps.year = mc.year::int AND ps.period = mc.period::int
WHERE mc.cdate::date = CURRENT_DATE
LIMIT 1