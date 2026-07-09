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

aggregated_flat_data AS (
    -- 🗜️ 2. MERAPATKAN DATA CY & LY MENJADI SATU BARIS HORIZONTAL
    SELECT 
        year, period, periodname, week,
        channel, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name,
        MAX(loaded_at) AS loaded_at,
        
        -- Data original mingguan (mentah tanpa digulung)
        SUM(CASE WHEN flag = 'cy' THEN target_qty ELSE 0 END) AS target_qty_orig,
        SUM(CASE WHEN flag = 'cy' THEN stm_qty ELSE 0 END) AS stm_qty_orig,
        SUM(CASE WHEN flag = 'cy' THEN salfo_qty ELSE 0 END) AS salfo_qty_orig,
        
        SUM(CASE WHEN flag = 'cy' THEN target_value ELSE 0 END) AS target_val_orig,
        SUM(CASE WHEN flag = 'cy' THEN stm_value ELSE 0 END) AS stm_val_orig,
        SUM(CASE WHEN flag = 'cy' THEN salfo_value ELSE 0 END) AS salfo_val_orig,
        
        -- Tarik jualan mingguan tahun lalu (ly) ke samping pada week yang sama
        SUM(CASE WHEN flag = 'ly' THEN stm_qty ELSE 0 END) AS stm_qty_ly_raw,
        SUM(CASE WHEN flag = 'ly' THEN stm_value ELSE 0 END) AS stm_val_ly_raw,
        
        -- Fitur Helper
        SUM(CASE WHEN flag = 'cy' THEN avg_5w_qty ELSE 0 END) AS avg_5w_qty,
        SUM(CASE WHEN flag = 'cy' THEN avg_5w_value ELSE 0 END) AS avg_5w_value,
        SUM(CASE WHEN flag = 'cy' THEN avg_13w_qty ELSE 0 END) AS avg_13w_qty,
        SUM(CASE WHEN flag = 'cy' THEN avg_13w_value ELSE 0 END) AS avg_13w_value
    FROM spx.silver_sales_performance_parent
    WHERE week IS NOT NULL
    GROUP BY 
        year, period, periodname, week,
        channel, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name
),

base_data_ytd AS (
    -- 🌟 3. PROSES GULUNGAN YTD & MTD (Nembak ke kolom _orig hasil aggregasi di atas)
    SELECT 
        a.*,
        -- Qty YTD
        SUM(a.target_qty_orig) OVER (PARTITION BY a.year, a.channel, a.sbu_id, a.grsm_id, a.rsm_id, a.ss_id, a.parent_id, a.brand_id, a.subbrand_id, a.flag_sku, a.distributor_id ORDER BY a.week) AS target_qty_ytd,
        SUM(a.stm_qty_orig) OVER (PARTITION BY a.year, a.channel, a.sbu_id, a.grsm_id, a.rsm_id, a.ss_id, a.parent_id, a.brand_id, a.subbrand_id, a.flag_sku, a.distributor_id ORDER BY a.week) AS stm_qty_ytd,
        SUM(a.stm_qty_ly_raw) OVER (PARTITION BY a.year, a.channel, a.sbu_id, a.grsm_id, a.rsm_id, a.ss_id, a.parent_id, a.brand_id, a.subbrand_id, a.flag_sku, a.distributor_id ORDER BY a.week) AS stm_qty_ytd_ly,
        
        -- Value YTD
        SUM(a.target_val_orig) OVER (PARTITION BY a.year, a.channel, a.sbu_id, a.grsm_id, a.rsm_id, a.ss_id, a.parent_id, a.brand_id, a.subbrand_id, a.flag_sku, a.distributor_id ORDER BY a.week) AS target_val_ytd,
        SUM(a.stm_val_orig) OVER (PARTITION BY a.year, a.channel, a.sbu_id, a.grsm_id, a.rsm_id, a.ss_id, a.parent_id, a.brand_id, a.subbrand_id, a.flag_sku, a.distributor_id ORDER BY a.week) AS stm_val_ytd,
        SUM(a.stm_val_ly_raw) OVER (PARTITION BY a.year, a.channel, a.sbu_id, a.grsm_id, a.rsm_id, a.ss_id, a.parent_id, a.brand_id, a.subbrand_id, a.flag_sku, a.distributor_id ORDER BY a.week) AS stm_val_ytd_ly,
        
        -- MTD Bulanan (Menggunakan kolom _orig)
        SUM(a.target_qty_orig) OVER (PARTITION BY a.year, a.period, a.channel, a.sbu_id, a.grsm_id, a.rsm_id, a.ss_id, a.parent_id, a.brand_id, a.subbrand_id, a.flag_sku, a.distributor_id ORDER BY a.week) AS target_qty_mtd,
        SUM(a.stm_qty_orig) OVER (PARTITION BY a.year, a.period, a.channel, a.sbu_id, a.grsm_id, a.rsm_id, a.ss_id, a.parent_id, a.brand_id, a.subbrand_id, a.flag_sku, a.distributor_id ORDER BY a.week) AS stm_qty_mtd,
        SUM(a.target_val_orig) OVER (PARTITION BY a.year, a.period, a.channel, a.sbu_id, a.grsm_id, a.rsm_id, a.ss_id, a.parent_id, a.brand_id, a.subbrand_id, a.flag_sku, a.distributor_id ORDER BY a.week) AS target_val_mtd,
        SUM(a.stm_val_orig) OVER (PARTITION BY a.year, a.period, a.channel, a.sbu_id, a.grsm_id, a.rsm_id, a.ss_id, a.parent_id, a.brand_id, a.subbrand_id, a.flag_sku, a.distributor_id ORDER BY a.week) AS stm_val_mtd,

        -- Target Statis Full Year (Menggunakan kolom _orig)
        SUM(a.target_qty_orig) OVER (PARTITION BY a.year, a.channel, a.sbu_id, a.grsm_id, a.rsm_id, a.ss_id, a.parent_id, a.brand_id, a.subbrand_id, a.flag_sku, a.distributor_id) AS target_qty_fy_statis,
        SUM(a.target_val_orig) OVER (PARTITION BY a.year, a.channel, a.sbu_id, a.grsm_id, a.rsm_id, a.ss_id, a.parent_id, a.brand_id, a.subbrand_id, a.flag_sku, a.distributor_id) AS target_val_fy_statis
    FROM aggregated_flat_data a
),

calculated_features AS (
    SELECT 
        b.*,
        LAG(b.target_qty_mtd, 4) OVER (PARTITION BY b.year, b.channel, b.sbu_id, b.grsm_id, b.rsm_id, b.ss_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku, b.distributor_id ORDER BY b.week) AS target_qty_lm,
        LAG(b.stm_qty_mtd, 4) OVER (PARTITION BY b.year, b.channel, b.sbu_id, b.grsm_id, b.rsm_id, b.ss_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku, b.distributor_id ORDER BY b.week) AS stm_qty_lm,
        LAG(b.target_val_mtd, 4) OVER (PARTITION BY b.year, b.channel, b.sbu_id, b.grsm_id, b.rsm_id, b.ss_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku, b.distributor_id ORDER BY b.week) AS target_val_lm,
        LAG(b.stm_val_mtd, 4) OVER (PARTITION BY b.year, b.channel, b.sbu_id, b.grsm_id, b.rsm_id, b.ss_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku, b.distributor_id ORDER BY b.week) AS stm_val_lm,

        c.cur_year, c.cur_period, c.cur_week
    FROM base_data_ytd b
    CROSS JOIN current_operational c
),

final_projections AS (
    SELECT 
        cl.*,
        CASE WHEN cl.week > 0 THEN ((cl.stm_qty_ytd + cl.salfo_qty_orig) / cl.week) * (52 - cl.week) ELSE 0 END AS est_stm_forward_qty,
        CASE WHEN cl.week > 0 THEN ((cl.stm_val_ytd + cl.salfo_val_orig) / cl.week) * (52 - cl.week) ELSE 0 END AS est_stm_forward_val
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
        
        target_qty_orig AS target_original,
        stm_qty_orig AS stm_original,
        salfo_qty_orig AS salfo_original,
        est_stm_forward_qty AS est_forward_original,
        
        target_qty_ytd AS target_ytd, 
        stm_qty_ytd AS stm_ytd, 
        stm_qty_ytd_ly AS stm_ytd_ly,
        target_qty_mtd AS target_mtd, 
        stm_qty_mtd AS stm_mtd,
        COALESCE(target_qty_lm, 0) AS target_lm, 
        COALESCE(stm_qty_lm, 0) AS stm_lm,
        avg_5w_qty AS avg_5w_value, 
        avg_13w_qty AS avg_13w_value,
        target_qty_fy_statis AS target_full_year_statis,
        (target_qty_ytd + salfo_qty_orig + est_stm_forward_qty) AS stm_est_fy,
        
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
        
        target_val_orig AS target_original,
        stm_val_orig AS stm_original,
        salfo_val_orig AS salfo_original,
        est_stm_forward_val AS est_forward_original,
        
        target_val_ytd AS target_ytd, 
        stm_val_ytd AS stm_ytd, 
        stm_val_ytd_ly AS stm_ytd_ly,
        target_val_mtd AS target_mtd, 
        stm_val_mtd AS stm_mtd,
        COALESCE(target_val_lm, 0) AS target_lm, 
        COALESCE(stm_val_lm, 0) AS stm_lm,
        avg_5w_value AS avg_5w_value, 
        avg_13w_value AS avg_13w_value,
        target_val_fy_statis AS target_full_year_statis,
        (target_val_ytd + salfo_val_orig + est_stm_forward_val) AS stm_est_fy,
        
        period AS min_urutan_period, 
        week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM final_projections
)
SELECT * FROM unpivoted