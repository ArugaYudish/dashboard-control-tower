{{ config(
    materialized='table',
    alias='gold_dashboard_sales_ssot',
    indexes=[
      {'columns': ['year', 'period', 'week', 'pilihan_satuan', 'channel', 'parent_id', 'distributor_id', 'grsm_id', 'rsm_id']}
    ]
) }}

WITH current_operational AS (
    -- 📅 1. KUNCIAN KALENDER OPERASIONAL HARI INI
    SELECT 
        year AS cur_year,
        period AS cur_period,
        week AS cur_week
    FROM spx.m_cycle3 
    WHERE cdate::date = CURRENT_DATE
    LIMIT 1
),

base_data_ytd AS (
    -- 🌟 2. GULUNG YTD & MTD MENGGUNAKAN WINDOW FUNCTION KHUSUS UNTUK CY DAN LY
    SELECT 
        s.*,
        -- 🔥 SEPARASI STRATEGIS: Hanya gulung data jika flag-nya sesuai embernya masing-masing
        SUM(CASE WHEN s.flag = 'cy' THEN s.target_qty ELSE 0 END) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS target_qty_ytd_cy,
        SUM(CASE WHEN s.flag = 'cy' THEN s.stm_qty ELSE 0 END) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS stm_qty_ytd_cy,
        SUM(CASE WHEN s.flag = 'ly' THEN s.stm_qty ELSE 0 END) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS stm_qty_ytd_ly,
        
        SUM(CASE WHEN s.flag = 'cy' THEN s.target_value ELSE 0 END) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS target_val_ytd_cy,
        SUM(CASE WHEN s.flag = 'cy' THEN s.stm_value ELSE 0 END) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS stm_val_ytd_cy,
        SUM(CASE WHEN s.flag = 'ly' THEN s.stm_value ELSE 0 END) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS stm_val_ytd_ly,
        
        -- MTD (Hanya untuk tahun berjalan / cy)
        SUM(CASE WHEN s.flag = 'cy' THEN s.target_qty ELSE 0 END) OVER (PARTITION BY s.year, s.period, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS target_qty_mtd,
        SUM(CASE WHEN s.flag = 'cy' THEN s.stm_qty ELSE 0 END) OVER (PARTITION BY s.year, s.period, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS stm_qty_mtd,
        SUM(CASE WHEN s.flag = 'cy' THEN s.target_value ELSE 0 END) OVER (PARTITION BY s.year, s.period, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS target_val_mtd,
        SUM(CASE WHEN s.flag = 'cy' THEN s.stm_value ELSE 0 END) OVER (PARTITION BY s.year, s.period, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS stm_val_mtd,

        -- Full Year Target Statis (Hanya untuk cy)
        SUM(CASE WHEN s.flag = 'cy' THEN s.target_qty ELSE 0 END) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id) AS target_qty_fy_statis,
        SUM(CASE WHEN s.flag = 'cy' THEN s.target_value ELSE 0 END) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id) AS target_val_fy_statis
    FROM spx.silver_sales_performance_parent s
    WHERE s.week IS NOT NULL
),

calculated_features AS (
    SELECT 
        b.*,
        -- Ambil data Last Month (LM) mundur 4 minggu
        LAG(b.target_qty_mtd, 4) OVER (PARTITION BY b.year, b.channel, b.sbu_id, b.grsm_id, b.rsm_id, b.ss_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku, b.distributor_id ORDER BY b.week) AS target_qty_lm,
        LAG(b.stm_qty_mtd, 4) OVER (PARTITION BY b.year, b.channel, b.sbu_id, b.grsm_id, b.rsm_id, b.ss_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku, b.distributor_id ORDER BY b.week) AS stm_qty_lm,
        LAG(b.target_val_mtd, 4) OVER (PARTITION BY b.year, b.channel, b.sbu_id, b.grsm_id, b.rsm_id, b.ss_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku, b.distributor_id ORDER BY b.week) AS target_val_lm,
        LAG(b.stm_val_mtd, 4) OVER (PARTITION BY b.year, b.channel, b.sbu_id, b.grsm_id, b.rsm_id, b.ss_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku, b.distributor_id ORDER BY b.week) AS stm_val_lm,

        c.cur_year, c.cur_period, c.cur_week
    FROM base_data_ytd b
    CROSS JOIN current_operational c
    -- 🌟 FILTER PENTING: Kita hanya men-generate baris utama dashboard dari data flag 'cy' saja!
    -- Data 'ly' otomatis sudah terserap masuk menjadi kolom via window function di atas.
    WHERE b.flag = 'cy'
),

final_projections AS (
    SELECT 
        cl.*,
        -- Estimasi Forward (Murni pakai data CY)
        CASE WHEN cl.week > 0 THEN ((cl.stm_qty_ytd_cy + cl.salfo_qty) / cl.week) * (52 - cl.week) ELSE 0 END AS est_stm_forward_qty,
        CASE WHEN cl.week > 0 THEN ((cl.stm_val_ytd_cy + cl.salfo_value) / cl.week) * (52 - cl.week) ELSE 0 END AS est_stm_forward_val
    FROM calculated_features cl
),

unpivoted AS (
    -- 🔵 UNPIVOT QTY
    SELECT 
        channel, year, period, periodname, week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        
        'QTY' AS pilihan_satuan,
        
        target_qty_ytd_cy AS target_ytd, 
        stm_qty_ytd_cy AS stm_ytd, 
        stm_qty_ytd_ly AS stm_ytd_ly, -- 🔥 AMAN SEJAJAR, TIDAK AKAN DUPLIKAT
        
        target_qty_mtd AS target_mtd, 
        stm_qty_mtd AS stm_mtd,
        
        COALESCE(target_qty_lm, 0) AS target_lm, 
        COALESCE(stm_qty_lm, 0) AS stm_lm,
        
        avg_5w_qty AS avg_5w_value, 
        avg_13w_qty AS avg_13w_value,
        
        target_qty_fy_statis AS target_full_year_statis,
        (stm_qty_ytd_cy + salfo_qty + est_stm_forward_qty) AS stm_est_fy,
        
        period AS min_urutan_period, 
        week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM final_projections

    UNION ALL

    -- 🟢 UNPIVOT VALUE
    SELECT 
        channel, year, period, periodname, week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        
        'VALUE' AS pilihan_satuan,
        
        target_val_ytd_cy AS target_ytd, 
        stm_val_ytd_cy AS stm_ytd, 
        stm_val_ytd_ly AS stm_ytd_ly, -- 🔥 AMAN SEJAJAR, TIDAK AKAN DUPLIKAT
        
        target_val_mtd AS target_mtd, 
        stm_val_mtd AS stm_mtd,
        
        COALESCE(target_val_lm, 0) AS target_lm, 
        COALESCE(stm_val_lm, 0) AS stm_lm,
        
        avg_5w_value AS avg_5w_value, 
        avg_13w_value AS avg_13w_value,
        
        target_val_fy_statis AS target_full_year_statis,
        (stm_val_ytd_cy + salfo_value + est_stm_forward_val) AS stm_est_fy,
        
        period AS min_urutan_period, 
        week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM final_projections
)
SELECT * FROM unpivoted