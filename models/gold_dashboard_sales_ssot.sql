{{ config(
    materialized='table',
    alias='gold_dashboard_sales_ssot',
    indexes=[
      {'columns': ['year', 'period', 'week', 'pilihan_satuan', 'channel', 'parent_id', 'distributor_id', 'grsm_id', 'rsm_id']}
    ]
) }}

WITH current_operational AS (
    -- 📅 1. JANGKAR WAKTU OPERASIONAL HARI INI
    SELECT 
        year::int AS cur_year,
        period::int AS cur_period,
        week::int AS cur_week
    FROM spx.m_cycle3 
    WHERE cdate::date = CURRENT_DATE
    LIMIT 1
),

linear_time_spine AS (
    -- 📉 2. KALKULASI TREN SECARA LINIER VERTIKAL (UNTUK MOVING AVERAGE 5W & 13W)
    SELECT 
        s.*,
        AVG(CASE WHEN s.year::int = 2026 AND s.week > c.cur_week THEN 0 ELSE s.stm_qty END) 
            OVER (PARTITION BY s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id 
                  ORDER BY s.year::int, s.week::int ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS avg_5w_qty_raw,
                  
        AVG(CASE WHEN s.year::int = 2026 AND s.week > c.cur_week THEN 0 ELSE s.stm_value END) 
            OVER (PARTITION BY s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id 
                  ORDER BY s.year::int, s.week::int ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS avg_5w_val_raw,
                  
        AVG(CASE WHEN s.year::int = 2026 AND s.week > c.cur_week THEN 0 ELSE s.stm_qty END) 
            OVER (PARTITION BY s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id 
                  ORDER BY s.year::int, s.week::int ROWS BETWEEN 12 PRECEDING AND CURRENT ROW) AS avg_13w_qty_raw,
                  
        AVG(CASE WHEN s.year::int = 2026 AND s.week > c.cur_week THEN 0 ELSE s.stm_value END) 
            OVER (PARTITION BY s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id 
                  ORDER BY s.year::int, s.week::int ROWS BETWEEN 12 PRECEDING AND CURRENT ROW) AS avg_13w_val_raw
    FROM spx.silver_sales_performance_parent s
    CROSS JOIN current_operational c
    WHERE s.year::int IN (2025, 2026) AND s.week IS NOT NULL
),

closing_period_data AS (
    -- 🛑 3. CTE PENGUNCI CLOSING: MENGHITUNG TOTAL 1 BULAN PENUH PER PERIODE (ANTI-LAG MELAR)
    SELECT 
        year::int AS cl_year,
        period::int AS cl_period,
        channel, parent_id, distributor_id, brand_id, subbrand_id, flag_sku,
        SUM(target_qty) AS total_target_qty_closing,
        SUM(stm_qty) AS total_stm_qty_closing,
        SUM(target_value) AS total_target_val_closing,
        SUM(stm_value) AS total_stm_val_closing
    FROM spx.silver_sales_performance_parent
    WHERE week IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
),

base_ty AS (
    -- 🔵 BLOK DATA TAHUN INI (2026) BERGULUNG SECARA INTERNAL
    SELECT 
        l.*,
        SUM(l.target_qty) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS target_qty_ytd_ty,
        SUM(CASE WHEN l.week::int <= c.cur_week THEN l.stm_qty ELSE 0 END) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS stm_qty_ytd_ty,
        
        SUM(l.target_value) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS target_val_ytd_ty,
        SUM(CASE WHEN l.week::int <= c.cur_week THEN l.stm_value ELSE 0 END) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS stm_val_ytd_ty,
        
        SUM(l.target_qty) OVER (PARTITION BY l.year, l.period, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS target_qty_mtd_ty,
        SUM(CASE WHEN l.week::int <= c.cur_week THEN l.stm_qty ELSE 0 END) OVER (PARTITION BY l.year, l.period, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS stm_qty_mtd_ty,
        
        SUM(l.target_value) OVER (PARTITION BY l.year, l.period, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS target_val_mtd_ty,
        SUM(CASE WHEN l.week::int <= c.cur_week THEN l.stm_value ELSE 0 END) OVER (PARTITION BY l.year, l.period, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS stm_val_mtd_ty,
        
        c.cur_year, c.cur_period, c.cur_week
    FROM linear_time_spine l
    CROSS JOIN current_operational c
    WHERE l.year::int = c.cur_year
),

base_ly AS (
    -- 🟢 BLOK DATA TAHUN LALU (2025) BERGULUNG SECARA INTERNAL
    SELECT 
        l.*,
        SUM(l.target_qty) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS target_qty_ytd_ly,
        SUM(l.stm_qty) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS stm_qty_ytd_ly,
        
        SUM(l.target_value) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, s.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS target_val_ytd_ly,
        SUM(l.stm_value) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS stm_val_ytd_ly
    FROM linear_time_spine l
    CROSS JOIN current_operational c
    WHERE l.year::int = (c.cur_year - 1)
),

horizontal_registry AS (
    -- 🗜️ 4. JOIN HORIZONTAL MUTLAK UNTUK MERAPATKAN DIMENSI CY, LY, DAN CLOSING LM
    SELECT 
        ty.year, ty.period, ty.periodname, ty.week,
        ty.channel, ty.nsm_id, ty.nsm_name, ty.grsm_id, ty.grsm_name, ty.rsm_id, ty.rsm_name, ty.ss_id, ty.ss_name,
        ty.sbu_id, ty.sbu_name, ty.brand_id, ty.brand_name, ty.subbrand_id, ty.subbrand_name, ty.parent_id, ty.parent_name,
        ty.flag_sku, ty.distributor_id, ty.distributor_name, ty.loaded_at,
        ty.cur_year, ty.cur_period, ty.cur_week,
        
        ty.target_qty AS target_qty_orig,
        ty.target_value AS target_val_orig,
        
        CASE WHEN ty.week::int <= ty.cur_week THEN ty.stm_qty ELSE 0 END AS stm_qty_orig,
        CASE WHEN ty.week::int <= ty.cur_week THEN ty.stm_value ELSE 0 END AS stm_val_orig,
        
        CASE WHEN ty.week::int > ty.cur_week THEN ty.salfo_qty ELSE 0 END AS est_forward_qty_orig,
        CASE WHEN ty.week::int > ty.cur_week THEN ty.salfo_value ELSE 0 END AS est_forward_val_orig,
        
        ty.target_qty_ytd_ty, ty.stm_qty_ytd_ty,
        ty.target_val_ytd_ty, ty.stm_val_ytd_ty,
        ty.target_qty_mtd_ty, ty.stm_qty_mtd_ty,
        ty.target_val_mtd_ty, ty.stm_val_mtd_ty,
        
        ty.avg_5w_qty_raw, ty.avg_5w_val_raw,
        ty.avg_13w_qty_raw, ty.avg_13w_val_raw,
        
        COALESCE(ly.target_qty, 0) AS target_qty_ly_orig,
        COALESCE(ly.target_value, 0) AS target_val_ly_orig,
        COALESCE(ly.stm_qty, 0) AS stm_qty_ly_orig,
        COALESCE(ly.stm_value, 0) AS stm_val_ly_orig,
        COALESCE(ly.target_qty_ytd_ly, 0) AS target_qty_ytd_ly,
        COALESCE(ly.stm_qty_ytd_ly, 0) AS stm_qty_ytd_ly,
        COALESCE(ly.target_val_ytd_ly, 0) AS target_val_ytd_ly,
        COALESCE(ly.stm_val_ytd_ly, 0) AS stm_val_ytd_ly,
        
        COALESCE(lm_internal.total_target_qty_closing, lm_cross.total_target_qty_closing, 0) AS target_qty_lm,
        COALESCE(lm_internal.total_stm_qty_closing, lm_cross.total_stm_qty_closing, 0) AS stm_qty_lm,
        COALESCE(lm_internal.total_target_val_closing, lm_cross.total_target_val_closing, 0) AS target_val_lm,
        COALESCE(lm_internal.total_stm_val_closing, lm_cross.total_stm_val_closing, 0) AS stm_val_lm,

        -- 🛡️ SELIPKAN SELURUH DATA INVENTORY & STOCK BAWAAN SILVER DI SINI
        ty.stock_qty, ty.stock_value, ty.stock_ibn, ty.stock_ibn_value, 
        ty.fdos_update, ty.fdos_value, ty.sta_qty, ty.sta_value

    FROM base_ty ty
    LEFT JOIN base_ly ly 
      ON ty.week::int = ly.week::int 
     AND ty.channel = ly.channel AND ty.parent_id = ly.parent_id AND ty.distributor_id = ly.distributor_id
     AND ty.brand_id = ly.brand_id AND ty.subbrand_id = ly.subbrand_id AND ty.flag_sku = ly.flag_sku
    LEFT JOIN closing_period_data lm_internal
      ON ty.year::int = lm_internal.cl_year
     AND ty.period::int = lm_internal.cl_period + 1
     AND ty.channel = lm_internal.channel AND ty.parent_id = lm_internal.parent_id AND ty.distributor_id = lm_internal.distributor_id
     AND ty.brand_id = lm_internal.brand_id AND ty.subbrand_id = lm_internal.subbrand_id AND ty.flag_sku = lm_internal.flag_sku
    LEFT JOIN closing_period_data lm_cross
      ON (ty.year::int - 1) = lm_cross.cl_year
     AND ty.period::int = 1 AND lm_cross.cl_period = 12
     AND ty.channel = lm_cross.channel AND ty.parent_id = lm_cross.parent_id AND ty.distributor_id = lm_cross.distributor_id
     AND ty.brand_id = lm_cross.brand_id AND ty.subbrand_id = lm_cross.subbrand_id AND ty.flag_sku = lm_cross.flag_sku
),

unpivoted AS (
    -- 🔵 UNPIVOT QTY
    SELECT 
        channel, year, period, periodname, week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        'QTY' AS pilihan_satuan,
        
        target_qty_orig AS target_original, stm_qty_orig AS stm_original, est_forward_qty_orig AS est_forward_original,
        target_qty_ly_orig AS target_original_ly, stm_qty_ly_orig AS stm_original_ly,
        target_qty_ytd_ty AS target_ytd, stm_qty_ytd_ty AS stm_ytd, 
        target_qty_ytd_ly AS target_ytd_ly, stm_qty_ytd_ly AS stm_ytd_ly,
        target_qty_mtd_ty AS target_mtd, stm_qty_mtd_ty AS stm_mtd,
        
        CASE WHEN week::int <= cur_week THEN target_qty_lm ELSE 0 END AS target_lm, 
        CASE WHEN week::int <= cur_week THEN stm_qty_lm ELSE 0 END AS stm_lm,
        CASE WHEN week::int <= cur_week THEN avg_5w_qty_raw ELSE 0 END AS avg_5w_value, 
        CASE WHEN week::int <= cur_week THEN avg_13w_qty_raw ELSE 0 END AS avg_13w_value,
        
        -- 📦 Oper Data Stock Qty Utuh ke Bawah
        stock_qty, stock_value, stock_ibn, stock_ibn_value, fdos_update, fdos_value, sta_qty, sta_value,
        
        period AS min_urutan_period, week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM horizontal_registry

    UNION ALL

    -- 🟢 UNPIVOT VALUE
    SELECT 
        channel, year, period, periodname, week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        'VALUE' AS pilihan_satuan,
        
        target_val_orig AS target_original, stm_val_orig AS stm_original, est_forward_val_orig AS est_forward_original,
        target_val_ly_orig AS target_original_ly, stm_val_ly_orig AS stm_original_ly,
        target_val_ytd_ty AS target_ytd, stm_val_ytd_ty AS stm_ytd, 
        target_val_ytd_ly AS target_ytd_ly, stm_val_ytd_ly AS stm_ytd_ly,
        target_val_mtd_ty AS target_mtd, stm_val_mtd_ty AS stm_mtd,
        
        CASE WHEN week::int <= cur_week THEN target_val_lm ELSE 0 END AS target_lm, 
        CASE WHEN week::int <= cur_week THEN stm_val_lm ELSE 0 END AS stm_lm,
        CASE WHEN week::int <= cur_week THEN avg_5w_val_raw ELSE 0 END AS avg_5w_value, 
        CASE WHEN week::int <= cur_week THEN avg_13w_val_raw ELSE 0 END AS avg_13w_value,
        
        -- 📦 Oper Data Stock Value Utuh ke Bawah
        stock_qty, stock_value, stock_ibn, stock_ibn_value, fdos_update, fdos_value, sta_qty, sta_value,
        
        period AS min_urutan_period, week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM horizontal_registry
)
SELECT * FROM unpivoted