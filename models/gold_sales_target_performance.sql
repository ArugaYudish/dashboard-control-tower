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
        year, period, week, pcode, op_current_year, op_current_period, op_current_week, is_ytd,
        'QTY' AS pilihan_satuan, 
        target_qty AS target_value_final, 
        stm_qty AS stm_value_final,
        COALESCE(salfo_qty, 0) AS salfo_value_final 
    FROM base_data
    
    UNION ALL
    
    -- Blok VALUE
    SELECT 
        year, period, week, pcode, op_current_year, op_current_period, op_current_week, is_ytd,
        'VALUE' AS pilihan_satuan, 
        target_value AS target_value_final, 
        stm_value AS stm_value_final,
        COALESCE(salfo_value, 0) AS salfo_value_final 
    FROM base_data
)

-- Trik Super Ngebut: Ambil data tahun lalu pakai LAG (Tanpa JOIN!)
SELECT 
    year,
    period,
    week,
    pcode,
    pilihan_satuan,
    op_current_year,
    op_current_period,
    op_current_week,
    is_ytd,
    target_value_final,
    stm_value_final,
    salfo_value_final,
    -- Mengintip data 1 baris di belakangnya (tahun sebelumnya) berdasarkan partisi SKU & Week yang sama
    COALESCE(
        LAG(stm_value_final, 1) OVER(
            PARTITION BY pcode, week, pilihan_satuan 
            ORDER BY year::numeric
        ), 0
    ) AS stm_value_ly_final
FROM unpivoted_data