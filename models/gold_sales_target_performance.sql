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
data_ty AS (
    SELECT 
        stp.*,
        c.cur_year AS op_current_year,
        c.cur_period AS op_current_period,
        c.cur_week AS op_current_week,
        CASE WHEN stp.week::numeric <= c.cur_week THEN 1 ELSE 0 END AS is_ytd
    FROM spx.silver_target_performance stp
    CROSS JOIN current_operational c
),
data_ly AS (
    SELECT 
        year, week, pcode, channel, distributor_id, -- Kunci keunikan baris data
        stm_qty, stm_value 
    FROM spx.silver_target_performance
),
matrix_combined AS (
    SELECT 
        t1.*, -- SEMUA KOLOM FILTER LENGKAP UTUH TERBAWA (Hierarki Sales, Brand, dll)
        COALESCE(t2.stm_qty, 0) AS stm_qty_ly,
        COALESCE(t2.stm_value, 0) AS stm_value_ly
    FROM data_ty t1
    LEFT JOIN data_ly t2 
        ON (t1.year::numeric - 1) = t2.year  -- Karena tipe datanya numeric, langsung kurangi tanpa cast text
       AND t1.week = t2.week 
       AND t1.pcode = t2.pcode
       -- KUNCI UTAMA: Mencegah Cartesian Product / Ledakan Data
       AND t1.channel = t2.channel
       AND t1.distributor_id = t2.distributor_id
)

-- PROSES UNPIVOT AKHIR
-- Blok QTY
SELECT 
    m.*,
    'QTY' AS pilihan_satuan, 
    m.target_qty AS target_value_final, 
    m.stm_qty AS stm_value_final,
    COALESCE(m.salfo_qty, 0) AS salfo_value_final,
    m.stm_qty_ly AS stm_value_ly_final
FROM matrix_combined m

UNION ALL

-- Blok VALUE
SELECT 
    m.*,
    'VALUE' AS pilihan_satuan, 
    m.target_value AS target_value_final, 
    m.stm_value AS stm_value_final,
    COALESCE(m.salfo_value, 0) AS salfo_value_final,
    m.stm_value_ly AS stm_value_ly_final
FROM matrix_combined m