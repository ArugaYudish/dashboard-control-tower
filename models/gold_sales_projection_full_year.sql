{{ config(
    materialized='table',
    alias='gold_sales_projection_full_year',
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

-- 1. AMBIL DRIVER TARGET UTUH 52 WEEK DARI MASTER TARGET
target_driver AS (
    SELECT 
        t.*,
        c.cur_year AS op_current_year,
        c.cur_period AS op_current_period,
        c.cur_week AS op_current_week,
        CASE WHEN t.week::numeric <= c.cur_week THEN 1 ELSE 0 END AS is_ytd_calc
    FROM spx.silver_target_performance t
    CROSS JOIN current_operational c
    WHERE t.year = 2026  -- Fokus murni untuk proyeksi forecast tahun berjalan
),

-- 2. AMBIL REALISASI STM & SALFO DARI SALES PERFORMANCE (YANG HANYA SAMPAI WEEK BERJALAN)
actual_sales AS (
    SELECT 
        week, pcode, channel, distributor_id,
        COALESCE(stm_qty, 0) AS stm_qty,
        COALESCE(stm_value, 0) AS stm_value,
        COALESCE(salfo_qty, 0) AS salfo_qty,
        COALESCE(salfo_value, 0) AS salfo_value
    FROM spx.silver_sales_performance
    WHERE year = 2026
),

-- 3. LEFT JOIN UNTUK MENJAGA WEEK MASA DEPAN TETAP AMAN DI DALAM DRIVER
combined_data AS (
    SELECT 
        t.channel, t.year, t.period::text AS period, t.periodname, t.week,
        t.nsm_id, t.nsm_name, t.grsm_id, t.grsm_name, t.rsm_id, t.rsm_name, t.ss_id, t.ss_name,
        t.sbu_id, t.sbu_name, t.brand_id, t.brand_name, t.subbrand_id, t.subbrand_name, t.parent_id, t.parent_name,
        t.pcode, t.pcodename, t.flag_sku, t.distributor_id, t.distributor_name,
        t.op_current_year, t.op_current_period, t.op_current_week, t.is_ytd_calc,
        
        -- Target mutlak 52 week dari driver
        COALESCE(t.target_qty, 0) AS target_qty,
        COALESCE(t.target_value, 0) AS target_value,
        
        -- Realisasi penjualan (akan otomatis NULL/0 untuk week masa depan, which is PERFECT)
        COALESCE(a.stm_qty, 0) AS stm_qty,
        COALESCE(a.stm_value, 0) AS stm_value,
        COALESCE(a.salfo_qty, 0) AS salfo_qty,
        COALESCE(a.salfo_value, 0) AS salfo_value
    FROM target_driver t
    LEFT JOIN actual_sales a 
        ON t.week = a.week 
       AND t.pcode = a.pcode 
       AND t.channel = a.channel 
       AND t.distributor_id = a.distributor_id
)

-- 4. UNPIVOT BLOCK
SELECT 
    *, 'QTY' AS pilihan_satuan,
    target_qty AS target_value_final,
    stm_qty AS stm_value_final,
    salfo_qty AS salfo_value_final
FROM combined_data

UNION ALL

SELECT 
    *, 'VALUE' AS pilihan_satuan,
    target_value AS target_value_final,
    stm_value AS stm_value_final,
    salfo_value AS salfo_value_final
FROM combined_data