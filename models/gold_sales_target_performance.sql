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
)

-- Proses menyatukan data horizontal (Melipat QTY dan VALUE)
, unpivoted_data AS (
    SELECT *, 'QTY' AS pilihan_satuan, target_qty AS target_final, stm_qty AS stm_final FROM base_data
    UNION ALL
    SELECT *, 'VALUE' AS pilihan_satuan, target_value AS target_final, stm_value AS stm_final FROM base_data
)

-- Trik Kunci: Menarik data STM Tahun Lalu ke baris Tahun Ini
SELECT 
    t1.year,
    t1.period,
    t1.week,
    t1.pcode,
    t1.pilihan_satuan,
    t1.op_current_year,
    t1.op_current_period,
    t1.op_current_week,
    t1.is_ytd,
    t1.target_final AS target_value_final,
    t1.stm_final AS stm_value_final,
    -- Kolom sakti: Mengambil nilai STM tahun lalu (Year - 1) pada week & pcode yang sama
    COALESCE(t2.stm_final, 0) AS stm_value_ly_final 
FROM unpivoted_data t1
LEFT JOIN unpivoted_data t2 
    ON t1.year::numeric = t2.year::numeric + 1 
   AND t1.week = t2.week 
   AND t1.pcode = t2.pcode 
   AND t1.pilihan_satuan = t2.pilihan_satuan;