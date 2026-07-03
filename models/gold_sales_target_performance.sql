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
-- 1. Ambil data utama (Tahun Ini) langsung dari Silver beserta flag YTD
data_ty AS (
    SELECT 
        stp.*,
        c.cur_year AS op_current_year,
        c.cur_period AS op_current_period,
        c.cur_week AS op_current_week,
        CASE WHEN stp.week::numeric <= c.cur_week THEN 1 ELSE 0 END AS is_ytd
    FROM spx.silver_target_performance stp
    CROSS JOIN current_operational c
)

-- 2. Langsung gabungkan secara horizontal dan lakukan unpivot di akhir
, matrix_combined AS (
    SELECT 
        t1.*,
        -- Mengambil langsung dari tabel fisik Silver untuk meminimalisir temporary space
        COALESCE(t2.stm_qty, 0) AS stm_qty_ly,
        COALESCE(t2.stm_value, 0) AS stm_value_ly
    FROM data_ty t1
    LEFT JOIN spx.silver_target_performance t2 
        ON (t1.year::numeric - 1)::text = t2.year::text  -- Mengunci indeks tahun lalu secara presisi
       AND t1.week = t2.week 
       AND t1.pcode = t2.pcode
)

-- 3. Blok Output Akhir (Seluruh kolom filter t1.* aman terbawa lengkap)
SELECT 
    m.*,
    'QTY' AS pilihan_satuan, 
    m.target_qty AS target_value_final, 
    m.stm_qty AS stm_value_final,
    COALESCE(m.salfo_qty, 0) AS salfo_value_final,
    m.stm_qty_ly AS stm_value_ly_final
FROM matrix_combined m

UNION ALL

SELECT 
    m.*,
    'VALUE' AS pilihan_satuan, 
    m.target_value AS target_value_final, 
    m.stm_value AS stm_value_final,
    COALESCE(m.salfo_value, 0) AS salfo_value_final,
    m.stm_value_ly AS stm_value_ly_final
FROM matrix_combined m