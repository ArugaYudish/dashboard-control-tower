{{ config(
    materialized='table',
    schema='spx',
    alias='gold_sales_target_performance',
    indexes=[
      {'columns': ['year', 'week', 'pcode', 'pilihan_satuan']}
    ]
) }}

WITH current_operational AS (
    SELECT 
        year::text AS cur_year,
        period::text AS cur_period,
        week::numeric AS cur_week
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
    FROM spx.silver_target_performance stp
    CROSS JOIN current_operational c
),
unpivoted_data AS (
    -- Blok QTY
    SELECT 
        b.*,
        'QTY' AS pilihan_satuan, 
        b.target_qty AS target_value_final, 
        b.stm_qty AS stm_value_final,
        COALESCE(b.salfo_qty, 0) AS salfo_value_final 
    FROM base_data b
    
    UNION ALL
    
    -- Blok VALUE
    SELECT 
        b.*,
        'VALUE' AS pilihan_satuan, 
        b.target_value AS target_value_final, 
        b.stm_value AS stm_value_final,
        COALESCE(b.salfo_value, 0) AS salfo_value_final 
    FROM base_data b
),
data_ty AS (
    SELECT * FROM unpivoted_data
),
data_ly AS (
    -- DI SINI PERBAIKANNYA: Menggunakan stm_value_final sesuai alias di atas
    SELECT year, week, pcode, pilihan_satuan, stm_value_final FROM unpivoted_data
)

-- Satukan secara horizontal
SELECT 
    t1.*, 
    COALESCE(t2.stm_value_final, 0) AS stm_value_ly_final 
FROM data_ty t1
LEFT JOIN data_ly t2 
    ON t1.year::numeric = t2.year::numeric + 1 
   AND t1.week = t2.week 
   AND t1.pcode = t2.pcode 
   AND t1.pilihan_satuan = t2.pilihan_satuan