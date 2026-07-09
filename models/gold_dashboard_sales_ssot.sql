{{ config(
    materialized='table',
    alias='gold_dashboard_sales_ssot',
    indexes=[
      {'columns': ['year', 'period', 'week', 'pilihan_satuan', 'channel', 'parent_id', 'distributor_id', 'rsm_id']}
    ]
) }}

WITH current_operational AS (
    SELECT 
        year::numeric AS cur_year,
        period::numeric AS cur_period,
        week::numeric AS cur_week
    FROM spx.m_cycle3 
    WHERE cdate::date = CURRENT_DATE
    LIMIT 1
),

-- Tarik 100% struktur murni Silver tanpa manipulasi baris sedikit pun
base_data AS (
    SELECT 
        s.*,
        c.cur_year AS op_current_year,
        c.cur_period AS op_current_period,
        c.cur_week AS op_current_week,
        CASE WHEN s.week::numeric <= c.cur_week THEN 1 ELSE 0 END AS is_ytd_calc,
        CASE WHEN c.cur_period = 1 THEN 12 ELSE (c.cur_period - 1) END AS op_last_period
    FROM spx.silver_sales_performance_parent s
    CROSS JOIN current_operational c
    WHERE s.week IS NOT NULL
),

-- Hitung helper target tahunan penuh yang dikunci super ketat sesuai unique baris aslinya
target_annual_helper AS (
    SELECT 
        year, channel, sbu_id, parent_id, brand_id, subbrand_id, flag_sku, distributor_id, nsm_id, grsm_id, rsm_id, ss_id,
        SUM(target_qty) AS target_qty_full_year,
        SUM(target_value) AS target_val_full_year
    FROM base_data
    GROUP BY year, channel, sbu_id, parent_id, brand_id, subbrand_id, flag_sku, distributor_id, nsm_id, grsm_id, rsm_id, ss_id
),

matrix_core AS (
    SELECT 
        bd.*,
        COALESCE(t.target_qty_full_year, 0) AS target_year_helper_qty,
        COALESCE(t.target_val_full_year, 0) AS target_year_helper_val
    FROM base_data bd
    LEFT JOIN target_annual_helper t 
        ON bd.year = t.year AND bd.channel = t.channel AND bd.sbu_id = t.sbu_id AND bd.parent_id = t.parent_id 
       AND bd.brand_id = t.brand_id AND bd.subbrand_id = t.subbrand_id AND bd.flag_sku = t.flag_sku 
       AND bd.distributor_id = t.distributor_id AND bd.nsm_id = t.nsm_id AND bd.grsm_id = t.grsm_id 
       AND bd.rsm_id = t.rsm_id AND bd.ss_id = t.ss_id
)

-- =========================================================================
-- 🔀 UNPIVOT BLOK DATA VERTIKAL SUPERSET (100% SAMA DENGAN BARIS SILVER)
-- =========================================================================

-- 🔵 1. BLOK DATA QTY
SELECT 
    channel, year, period, periodname, week,
    nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
    sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
    flag_sku, distributor_id, distributor_name, loaded_at,
    op_current_year, op_current_period, op_current_week, is_ytd_calc, op_last_period,
    
    'QTY' AS pilihan_satuan,
    target_qty AS target_weekly,
    salfo_qty AS salfo_weekly,
    stm_qty AS stm_weekly,
    stock_ibn AS stock_ibn,
    stock_ibn_value AS stock_ibn_value_raw,
    fdos_update AS fdos_update,
    fdos_value AS fdos_value_raw,
    sta_qty AS sta_weekly,
    stock_qty AS stock_weekly,
    stock_value AS stock_value_raw,
    avg_5w_qty AS avg_5w,
    avg_5w_value AS avg_5w_value_raw,
    avg_13w_qty AS avg_13w,
    avg_13w_value AS avg_13w_value_raw,
    avg_5w_sta_qty AS avg_5w_sta,
    avg_5w_sta_value AS avg_5w_sta_value_raw,
    
    0 AS target_weekly_lm,
    0 AS stm_weekly_lm,
    0 AS salfo_weekly_lm,
    0 AS target_weekly_ly,
    0 AS stm_weekly_ly,
    0 AS salfo_weekly_ly,
    
    target_year_helper_qty AS target_full_year_statis,
    0 AS ytd_sales_statis,

    CASE WHEN period::numeric = op_current_period THEN 0 ELSE period::numeric END AS urutan_filter_period,
    CASE WHEN week::numeric = op_current_week THEN 0 ELSE week::numeric END AS urutan_filter_week,

    -- Menggunakan nilai murni mingguan untuk di-sum secara dinamis di Superset YTD
    target_qty AS target_ytd_mateng,
    stm_qty AS stm_ytd_mateng
FROM matrix_core

UNION ALL

-- 🟢 2. BLOK DATA VALUE
SELECT 
    channel, year, period, periodname, week,
    nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
    sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
    flag_sku, distributor_id, distributor_name, loaded_at,
    op_current_year, op_current_period, op_current_week, is_ytd_calc, op_last_period,
    
    'VALUE' AS pilihan_satuan,
    target_value AS target_weekly,
    salfo_value AS salfo_weekly,
    stm_value AS stm_weekly,
    stock_ibn_value AS stock_ibn,
    stock_ibn_value AS stock_ibn_value_raw,
    fdos_value AS fdos_update,
    fdos_value AS fdos_value_raw,
    sta_value AS sta_weekly,
    stock_qty AS stock_weekly,
    stock_value AS stock_value_raw,
    avg_5w_value AS avg_5w,
    avg_5w_value AS avg_5w_value_raw,
    avg_13w_value AS avg_13w,
    avg_13w_value AS avg_13w_value_raw,
    avg_5w_sta_value AS avg_5w_sta,
    avg_5w_sta_value AS avg_5w_sta_value_raw,
    
    0 AS target_weekly_lm,
    0 AS stm_weekly_lm,
    0 AS salfo_weekly_lm,
    0 AS target_weekly_ly,
    0 AS stm_weekly_ly,
    0 AS salfo_weekly_ly,
    
    target_year_helper_val AS target_full_year_statis,
    0 AS ytd_sales_statis,

    CASE WHEN period::numeric = op_current_period THEN 0 ELSE period::numeric END AS urutan_filter_period,
    CASE WHEN week::numeric = op_current_week THEN 0 ELSE week::numeric END AS urutan_filter_week,

    target_value AS target_ytd_mateng,
    stm_value AS stm_ytd_mateng
FROM matrix_core