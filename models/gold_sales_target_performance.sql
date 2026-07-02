{{ config(
    materialized='table',
    alias='gold_sales_target_performance',
    indexes=[
      {'columns': ['year', 'week', 'pcode', 'pilihan_satuan']}
    ]
) }}

WITH current_operational AS (
    SELECT 
        year::text AS cur_year,
        period::text AS cur_period,
        week::numeric AS cur_week,
        (year - 1)::text AS last_year
    FROM spx.m_cycle3 
    WHERE cdate::date = CURRENT_DATE
    LIMIT 1
),
base_data AS (
    SELECT 
        stp.*,
        c.cur_year AS op_current_year,
        c.cur_period AS op_current_period,
        c.cur_week AS op_current_week,
        CASE WHEN stp.week::numeric <= c.cur_week THEN 1 ELSE 0 END AS is_ytd
    -- Menggunakan nama tabel mentah (Bypass YAML)
    FROM spx.silver_target_performance stp
    CROSS JOIN current_operational c
    WHERE stp.year::text IN (c.cur_year, c.last_year)
)

-- Blok QTY
SELECT 
    *,
    'QTY' AS pilihan_satuan,
    target_qty AS target_value_final,
    stm_qty AS stm_value_final,
    COALESCE(salfo_qty, 0) AS salfo_value_final
FROM base_data

UNION ALL

-- Blok VALUE
SELECT 
    *,
    'VALUE' AS pilihan_satuan,
    target_value AS target_value_final,
    stm_value AS stm_value_final,
    COALESCE(salfo_value, 0) AS salfo_value_final
FROM base_data