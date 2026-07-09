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

base_with_op AS (
    SELECT 
        s.*,
        c.cur_year AS op_current_year,
        c.cur_period AS op_current_period,
        c.cur_week AS op_current_week,
        CASE WHEN s.week <= c.cur_week THEN 1 ELSE 0 END AS is_ytd_calc,
        CASE WHEN c.cur_period = 1 THEN 12 ELSE (c.cur_period - 1) END AS op_last_period
    FROM spx.silver_sales_performance_parent s
    CROSS JOIN current_operational c
    WHERE s.week IS NOT NULL AND s.week != 0
),

-- =========================================================================
-- ⚡ STEP KUNCIAN GLOBAL BULANAN & TAHUNAN (Helper Statis Level Atas)
-- =========================================================================
kuncian_global AS (
    SELECT 
        year, channel,
        SUM(target_qty) AS target_qty_full_year,
        SUM(target_value) AS target_val_full_year,
        SUM(CASE WHEN week <= op_current_week THEN stm_qty + salfo_qty ELSE 0 END) AS ytd_sales_qty_pure,
        SUM(CASE WHEN week <= op_current_week THEN stm_value + salfo_value ELSE 0 END) AS ytd_sales_val_pure
    FROM base_with_op
    GROUP BY year, channel
),

-- =========================================================================
-- 🔑 STEP AKUMULASI SEJATI (WINDOW FUNCTION LOCK TOTAL PK DASHBOARD)
-- =========================================================================
matrix_cumulative AS (
    SELECT 
        b.*,
        -- Mengakumulasikan data dari Week 1 s/d Week berjalan murni per Unique Row Identity
        SUM(b.target_qty) OVER (
            PARTITION BY 
                b.channel, b.year, b.sbu_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku,
                b.distributor_id, b.nsm_id, b.grsm_id, b.rsm_id, b.ss_id
            ORDER BY b.week
        ) AS target_qty_ytd_cum,
        
        SUM(b.target_value) OVER (
            PARTITION BY 
                b.channel, b.year, b.sbu_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku,
                b.distributor_id, b.nsm_id, b.grsm_id, b.rsm_id, b.ss_id
            ORDER BY b.week
        ) AS target_val_ytd_cum,
        
        SUM(b.stm_qty) OVER (
            PARTITION BY 
                b.channel, b.year, b.sbu_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku,
                b.distributor_id, b.nsm_id, b.grsm_id, b.rsm_id, b.ss_id
            ORDER BY b.week
        ) AS stm_qty_ytd_cum,
        
        SUM(b.stm_value) OVER (
            PARTITION BY 
                b.channel, b.year, b.sbu_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku,
                b.distributor_id, b.nsm_id, b.grsm_id, b.rsm_id, b.ss_id
            ORDER BY b.week
        ) AS stm_val_ytd_cum
    FROM base_with_op b
),

matrix_core AS (
    SELECT 
        mc.*,
        COALESCE(k.target_qty_full_year, 0) AS target_year_helper_qty,
        COALESCE(k.target_val_full_year, 0) AS target_year_helper_val,
        COALESCE(k.ytd_sales_qty_pure, 0) AS ytd_sales_helper_qty,
        COALESCE(k.ytd_sales_val_pure, 0) AS ytd_sales_helper_val
    FROM matrix_cumulative mc
    LEFT JOIN kuncian_global k ON mc.year = k.year AND mc.channel = k.channel
),

kuncian_bulanan AS (
    SELECT 
        year, period, channel, distributor_id, parent_id,
        SUM(target_qty) AS target_qty_lm_raw,
        SUM(target_value) AS target_val_lm_raw,
        SUM(stm_qty) AS stm_qty_lm_raw,
        SUM(stm_value) AS stm_value_lm_raw,
        SUM(salfo_qty) AS salfo_qty_lm_raw,
        SUM(salfo_value) AS salfo_value_lm_raw
    FROM matrix_core
    GROUP BY year, period, channel, distributor_id, parent_id
),

matrix_with_ly_and_lm AS (
    SELECT 
        curr.*,
        COALESCE(ly.stm_qty, 0) AS stm_qty_ly,
        COALESCE(ly.stm_value, 0) AS stm_value_ly,
        COALESCE(ly.salfo_qty, 0) AS salfo_qty_ly,
        COALESCE(ly.salfo_value, 0) AS salfo_value_ly,
        COALESCE(ly.target_qty, 0) AS target_qty_ly,
        COALESCE(ly.target_value, 0) AS target_value_ly,
        
        COALESCE(lm.target_qty_lm_raw, 0) AS target_qty_lm,
        COALESCE(lm.target_val_lm_raw, 0) AS target_value_lm,
        COALESCE(lm.stm_qty_lm_raw, 0) AS stm_qty_lm,
        COALESCE(lm.stm_value_lm_raw, 0) AS stm_value_lm,
        COALESCE(lm.salfo_qty_lm_raw, 0) AS salfo_qty_lm,
        COALESCE(lm.salfo_value_lm_raw, 0) AS salfo_value_lm
    FROM matrix_core curr
    LEFT JOIN matrix_core ly
        ON ly.channel = curr.channel
       AND ly.distributor_id = curr.distributor_id
       AND ly.parent_id = curr.parent_id
       AND ly.year = (curr.year - 1)
       AND ly.period = curr.period
       AND ly.week = curr.week
    LEFT JOIN kuncian_bulanan lm
        ON lm.channel = curr.channel
       AND lm.distributor_id = curr.distributor_id
       AND lm.parent_id = curr.parent_id
       AND lm.year = curr.year
       AND lm.period = (curr.period - 1)
)

-- =========================================================================
-- 🔀 UNPIVOT BLOK DATA VERTIKAL SUPERSET
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
    
    target_qty_lm AS target_weekly_lm,
    stm_qty_lm AS stm_weekly_lm,
    salfo_qty_lm AS salfo_weekly_lm,
    
    target_qty_ly AS target_weekly_ly,
    stm_qty_ly AS stm_weekly_ly,
    salfo_qty_ly AS salfo_weekly_ly,
    
    target_year_helper_qty AS target_full_year_statis,
    ytd_sales_helper_qty AS ytd_sales_statis,

    CASE WHEN period::numeric = op_current_period THEN 0 ELSE period::numeric END AS urutan_filter_period,
    CASE WHEN week::numeric = op_current_week THEN 0 ELSE week::numeric END AS urutan_filter_week,

    -- 💎 Kolom Mateng Hasil Kuncian Total PK
    target_qty_ytd_cum AS target_ytd_mateng,
    stm_qty_ytd_cum AS stm_ytd_mateng
FROM matrix_with_ly_and_lm

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
    stock_value AS stock_weekly,
    stock_value AS stock_value_raw,
    avg_5w_value AS avg_5w,
    avg_5w_value AS avg_5w_value_raw,
    avg_13w_value AS avg_13w,
    avg_13w_value AS avg_13w_value_raw,
    avg_5w_sta_value AS avg_5w_sta,
    avg_5w_sta_value AS avg_5w_sta_value_raw,
    
    target_value_lm AS target_weekly_lm,
    stm_value_lm AS stm_weekly_lm,
    salfo_value_lm AS salfo_weekly_lm,
    
    target_value_ly AS target_weekly_ly,
    stm_value_ly AS stm_weekly_ly,
    salfo_value_ly AS salfo_weekly_ly,
    
    target_year_helper_val AS target_full_year_statis,
    ytd_sales_helper_val AS ytd_sales_statis,

    CASE WHEN period::numeric = op_current_period THEN 0 ELSE period::numeric END AS urutan_filter_period,
    CASE WHEN week::numeric = op_current_week THEN 0 ELSE week::numeric END AS urutan_filter_week,

    -- 💎 Kolom Mateng Hasil Kuncian Total PK
    target_val_ytd_cum AS target_ytd_mateng,
    stm_val_ytd_cum AS stm_ytd_mateng
FROM matrix_with_ly_and_lm