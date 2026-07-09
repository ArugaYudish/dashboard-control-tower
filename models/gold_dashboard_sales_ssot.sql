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

-- 1. Ambil list kombinasi Year dan Week yang valid secara dinamis dari Silver
all_weeks AS (
    SELECT DISTINCT 
        year AS spine_year,
        week::numeric AS spine_week 
    FROM spx.silver_sales_performance_parent 
    WHERE week IS NOT NULL
),

-- 2. Ambil master filter lengkap per tahun secara dinamis
distinct_combos AS (
    SELECT DISTINCT
        channel, year, period, periodname,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name
    FROM spx.silver_sales_performance_parent
),

-- 3. Tiup Backbone Grid Multi-Year Dinamis: Dikunci berpasangan berdasarkan kolom YEAR
spine AS (
    SELECT c.*, w.spine_week
    FROM distinct_combos c
    INNER JOIN all_weeks w 
        ON c.year = w.spine_year
),

-- 4. Tempelkan jualan riil Silver ke atas tulang punggung matriks hantu multi-year
joined_data AS (
    SELECT 
        s.*,
        COALESCE(actual.target_qty, 0) AS target_qty_raw,
        COALESCE(actual.stm_qty, 0) AS stm_qty_raw,
        COALESCE(actual.target_value, 0) AS target_val_raw,
        COALESCE(actual.stm_value, 0) AS stm_val_raw,
        c.cur_year AS op_current_year,
        c.cur_period AS op_current_period,
        c.cur_week AS op_current_week,
        CASE WHEN s.spine_week <= c.cur_week THEN 1 ELSE 0 END AS is_ytd_calc,
        CASE WHEN c.cur_period = 1 THEN 12 ELSE (c.cur_period - 1) END AS op_last_period
    FROM spine s
    LEFT JOIN spx.silver_sales_performance_parent actual
        ON s.channel = actual.channel 
       AND s.year = actual.year 
       AND s.spine_week = actual.week::numeric
       AND s.sbu_id = actual.sbu_id 
       AND s.parent_id = actual.parent_id 
       AND s.brand_id = actual.brand_id 
       AND s.subbrand_id = actual.subbrand_id 
       AND s.flag_sku = actual.flag_sku 
       AND s.distributor_id = actual.distributor_id
       AND s.ss_id = actual.ss_id 
       AND s.rsm_id = actual.rsm_id
    CROSS JOIN current_operational c
),

-- 5. Gulung incremental per tahun dan per entitas filter lengkap tanpa ada sekat bolong
matrix_cumulative AS (
    SELECT 
        j.*,
        SUM(j.target_qty_raw::numeric(20,4)) OVER (
            PARTITION BY j.channel, j.year, j.sbu_id, j.parent_id, j.brand_id, j.subbrand_id, j.flag_sku, j.distributor_id, j.rsm_id, j.ss_id
            ORDER BY j.spine_week
        ) AS target_qty_ytd_cum,
        SUM(j.stm_qty_raw::numeric(20,4)) OVER (
            PARTITION BY j.channel, j.year, j.sbu_id, j.parent_id, j.brand_id, j.subbrand_id, j.flag_sku, j.distributor_id, j.rsm_id, j.ss_id
            ORDER BY j.spine_week
        ) AS stm_qty_ytd_cum,
        SUM(j.target_val_raw::numeric(20,4)) OVER (
            PARTITION BY j.channel, j.year, j.sbu_id, j.parent_id, j.brand_id, j.subbrand_id, j.flag_sku, j.distributor_id, j.rsm_id, j.ss_id
            ORDER BY j.spine_week
        ) AS target_val_ytd_cum,
        SUM(j.stm_val_raw::numeric(20,4)) OVER (
            PARTITION BY j.channel, j.year, j.sbu_id, j.parent_id, j.brand_id, j.subbrand_id, j.flag_sku, j.distributor_id, j.rsm_id, j.ss_id
            ORDER BY j.spine_week
        ) AS stm_val_ytd_cum
    FROM joined_data j
),

-- 6. Helper Target Setahun Penuh (Dinamis per Tahun)
matrix_core AS (
    SELECT 
        mc.*,
        COALESCE(t.target_qty_full_year, 0) AS target_year_helper_qty,
        COALESCE(t.target_val_full_year, 0) AS target_year_helper_val
    FROM matrix_cumulative mc
    LEFT JOIN (
        SELECT 
            year, channel, sbu_id, parent_id, brand_id, subbrand_id, flag_sku, distributor_id, rsm_id, ss_id,
            SUM(target_qty::numeric(20,4)) AS target_qty_full_year,
            SUM(target_value::numeric(20,4)) AS target_val_full_year
        FROM spx.silver_sales_performance_parent
        GROUP BY year, channel, sbu_id, parent_id, brand_id, subbrand_id, flag_sku, distributor_id, rsm_id, ss_id
    ) t ON mc.year = t.year AND mc.channel = t.channel AND mc.sbu_id = t.sbu_id AND mc.parent_id = t.parent_id 
       AND mc.brand_id = t.brand_id AND mc.subbrand_id = t.subbrand_id AND mc.flag_sku = t.flag_sku 
       AND mc.distributor_id = t.distributor_id AND mc.nsm_id = t.nsm_id AND mc.grsm_id = t.grsm_id 
       AND mc.rsm_id = t.rsm_id AND mc.ss_id = t.ss_id
)

-- =========================================================================
-- 🔀 UNPIVOT BLOK DATA VERTIKAL SUPERSET
-- =========================================================================

-- 🔵 1. BLOK DATA QTY
SELECT 
    channel, year, period, periodname, spine_week AS week,
    nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
    sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
    flag_sku, distributor_id, distributor_name, NOW() AS loaded_at,
    op_current_year, op_current_period, op_current_week, is_ytd_calc, op_last_period,
    
    'QTY' AS pilihan_satuan,
    target_qty_raw AS target_weekly,
    0 AS salfo_weekly, 
    stm_qty_raw AS stm_weekly,
    0 AS stock_ibn,
    0 AS stock_ibn_value_raw,
    0 AS fdos_update,
    0 AS fdos_value_raw,
    0 AS sta_weekly,
    0 AS stock_qty,
    0 AS stock_value_raw,
    0 AS avg_5w,
    0 AS avg_5w_value_raw,
    0 AS avg_13w,
    0 AS avg_13w_value_raw,
    0 AS avg_5w_sta,
    0 AS avg_5w_sta_value_raw,
    
    0 AS target_weekly_lm,
    0 AS stm_weekly_lm,
    0 AS salfo_weekly_lm,
    0 AS target_weekly_ly,
    0 AS stm_weekly_ly,
    0 AS salfo_weekly_ly,
    
    target_year_helper_qty AS target_full_year_statis,
    0 AS ytd_sales_statis,

    CASE WHEN period::numeric = op_current_period THEN 0 ELSE period::numeric END AS urutan_filter_period,
    CASE WHEN spine_week = op_current_week THEN 0 ELSE spine_week END AS urutan_filter_week,

    target_qty_ytd_cum AS target_ytd_mateng,
    stm_qty_ytd_cum AS stm_ytd_mateng
FROM matrix_core

UNION ALL

-- 🟢 2. BLOK DATA VALUE (SUDAH FIXED DARI TYPO DOUBLE AS)
SELECT 
    channel, year, period, periodname, spine_week AS week,
    nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
    sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
    flag_sku, distributor_id, distributor_name, NOW() AS loaded_at,
    op_current_year, op_current_period, op_current_week, is_ytd_calc, op_last_period,
    
    'VALUE' AS pilihan_satuan,
    target_val_raw AS target_weekly,
    0 AS salfo_weekly,
    stm_val_raw AS stm_weekly,
    0 AS stock_ibn,
    0 AS stock_ibn_value_raw,
    0 AS fdos_update,
    0 AS fdos_value_raw,
    0 AS sta_weekly,
    0 AS stock_qty,
    0 AS stock_value_raw,
    0 AS avg_5w, -- <-- FIXED BARIS SAKTI DISINI, BRO!
    0 AS avg_5w_value_raw,
    0 AS avg_13w,
    0 AS avg_13w_value_raw,
    0 AS avg_5w_sta,
    0 AS avg_5w_sta_value_raw,
    
    0 AS target_weekly_lm,
    0 AS stm_weekly_lm,
    0 AS salfo_weekly_lm,
    0 AS target_weekly_ly,
    0 AS stm_weekly_ly,
    0 AS salfo_weekly_ly,
    
    target_year_helper_val AS target_full_year_statis,
    0 AS ytd_sales_statis,

    CASE WHEN period::numeric = op_current_period THEN 0 ELSE period::numeric END AS urutan_filter_period,
    CASE WHEN spine_week = op_current_week THEN 0 ELSE spine_week END AS urutan_filter_week,

    target_val_ytd_cum AS target_ytd_mateng,
    stm_val_ytd_cum AS stm_ytd_mateng
FROM matrix_core