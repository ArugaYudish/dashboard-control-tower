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

-- 🏗️ 2. MEMBANGUN DENSE GRID (TULANG PUNGGUNG WAKTU & DIMENSI YANG PADAT)
calendar_spine AS (
    SELECT DISTINCT 
        year::int AS year, 
        period::int AS period, 
        periodname, 
        week::int AS week
    FROM spx.m_cycle3
    WHERE year::int IN (2025, 2026)
),

dim_spine AS (
    SELECT DISTINCT 
        channel, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name
    FROM spx.silver_sales_performance_parent
    WHERE year::int IN (2025, 2026)
),

dense_grid AS (
    SELECT c.year, c.period, c.periodname, c.week, d.*
    FROM calendar_spine c
    CROSS JOIN dim_spine d
),

silver_dense AS (
    SELECT 
        g.year, g.period, g.periodname, g.week,
        g.channel, g.nsm_id, g.nsm_name, g.grsm_id, g.grsm_name, g.rsm_id, g.rsm_name, g.ss_id, g.ss_name,
        g.sbu_id, g.sbu_name, g.brand_id, g.brand_name, g.subbrand_id, g.subbrand_name, g.parent_id, g.parent_name,
        g.flag_sku, g.distributor_id, g.distributor_name,
        
        COALESCE(s.target_qty, 0) AS target_qty,
        COALESCE(s.stm_qty, 0) AS stm_qty,
        COALESCE(s.target_value, 0) AS target_value,
        COALESCE(s.stm_value, 0) AS stm_value,
        COALESCE(s.salfo_qty, 0) AS salfo_qty,
        COALESCE(s.salfo_value, 0) AS salfo_value,
        s.loaded_at
    FROM dense_grid g
    LEFT JOIN spx.silver_sales_performance_parent s
      ON g.year = s.year::int 
     AND g.week = s.week::int
     AND g.distributor_id = s.distributor_id 
     AND g.flag_sku = s.flag_sku 
     AND g.channel = s.channel
),

linear_time_spine AS (
    -- 📉 3. KALKULASI TREN SECARA LINIER VERTIKAL (MOVING AVERAGE VIA DENSE DATA)
    SELECT 
        s.*,
        AVG(CASE WHEN s.year = 2026 AND s.week > c.cur_week THEN 0 ELSE s.stm_qty END) 
            OVER (PARTITION BY s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id 
                  ORDER BY s.year, s.week ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS avg_5w_qty_raw,
                  
        AVG(CASE WHEN s.year = 2026 AND s.week > c.cur_week THEN 0 ELSE s.stm_value END) 
            OVER (PARTITION BY s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id 
                  ORDER BY s.year, s.week ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS avg_5w_val_raw,
                  
        AVG(CASE WHEN s.year = 2026 AND s.week > c.cur_week THEN 0 ELSE s.stm_qty END) 
            OVER (PARTITION BY s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id 
                  ORDER BY s.year, s.week ROWS BETWEEN 12 PRECEDING AND CURRENT ROW) AS avg_13w_qty_raw,
                  
        AVG(CASE WHEN s.year = 2026 AND s.week > c.cur_week THEN 0 ELSE s.stm_value END) 
            OVER (PARTITION BY s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id 
                  ORDER BY s.year, s.week ROWS BETWEEN 12 PRECEDING AND CURRENT ROW) AS avg_13w_val_raw
    FROM silver_dense s
    CROSS JOIN current_operational c
    WHERE s.year IN (2025, 2026)
),

closing_period_data AS (
    -- 🛑 4. CTE PENGUNCI CLOSING (Continuous Period Index untuk penyeberangan akhir tahun)
    SELECT 
        year,
        period,
        ((year * 12) + period) AS continuous_period_id,
        channel, parent_id, distributor_id, brand_id, subbrand_id, flag_sku,
        SUM(target_qty) AS total_target_qty_closing,
        SUM(stm_qty) AS total_stm_qty_closing,
        SUM(target_value) AS total_target_val_closing,
        SUM(stm_value) AS total_stm_val_closing
    FROM silver_dense
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),

base_ty AS (
    -- 🔵 BLOK DATA TAHUN INI (2026) BERGULUNG SECARA INTERNAL
    SELECT 
        l.*,
        SUM(l.target_qty) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS target_qty_ytd_ty,
        SUM(CASE WHEN l.week <= c.cur_week THEN l.stm_qty ELSE 0 END) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS stm_qty_ytd_ty,
        
        SUM(l.target_value) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS target_val_ytd_ty,
        SUM(CASE WHEN l.week <= c.cur_week THEN l.stm_value ELSE 0 END) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS stm_val_ytd_ty,
        
        SUM(l.target_qty) OVER (PARTITION BY l.year, l.period, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS target_qty_mtd_ty,
        SUM(CASE WHEN l.week <= c.cur_week THEN l.stm_qty ELSE 0 END) OVER (PARTITION BY l.year, l.period, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS stm_qty_mtd_ty,
        
        SUM(l.target_value) OVER (PARTITION BY l.year, l.period, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS target_val_mtd_ty,
        SUM(CASE WHEN l.week <= c.cur_week THEN l.stm_value ELSE 0 END) OVER (PARTITION BY l.year, l.period, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS stm_val_mtd_ty,
        
        -- ✨ HELPER LOCK: Target Full Year (Dikunci murni per tahun)
        SUM(l.target_qty) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id) AS target_qty_fy,
        SUM(l.target_value) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id) AS target_val_fy,

        -- ✨ HELPER CALCULATED: Proyeksi Run Rate Masa Depan
        (SUM(CASE WHEN l.week <= c.cur_week THEN l.stm_qty ELSE 0 END) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / NULLIF(c.cur_week, 0)) AS avg_qty_per_week_ytd,
        (SUM(CASE WHEN l.week <= c.cur_week THEN l.stm_value ELSE 0 END) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / NULLIF(c.cur_week, 0)) AS avg_val_per_week_ytd,
        
        (52 - c.cur_week) AS remaining_weeks_in_year,
        
        c.cur_year, c.cur_period, c.cur_week
    FROM linear_time_spine l
    CROSS JOIN current_operational c
    WHERE l.year = c.cur_year
),

base_ly AS (
    -- 🟢 BLOK DATA TAHUN LALU (2025) BERGULUNG SECARA INTERNAL
    SELECT 
        l.*,
        SUM(l.target_qty) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS target_qty_ytd_ly,
        SUM(l.stm_qty) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS stm_qty_ytd_ly,
        
        SUM(l.target_value) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS target_val_ytd_ly,
        SUM(l.stm_value) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS stm_val_ytd_ly,
        
        SUM(l.target_qty) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id) AS target_qty_fy_ly,
        SUM(l.target_value) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id) AS target_val_fy_ly
    FROM linear_time_spine l
    CROSS JOIN current_operational c
    WHERE l.year = (c.cur_year - 1)
),

horizontal_registry AS (
    -- 🗜️ 5. JOIN HORIZONTAL MUTLAK CY, LY, DAN CLOSING LM
    SELECT 
        ty.year, ty.period, ty.periodname, ty.week,
        ty.channel, ty.nsm_id, ty.nsm_name, ty.grsm_id, ty.grsm_name, ty.rsm_id, ty.rsm_name, ty.ss_id, ty.ss_name,
        ty.sbu_id, ty.sbu_name, ty.brand_id, ty.brand_name, ty.subbrand_id, ty.subbrand_name, ty.parent_id, ty.parent_name,
        ty.flag_sku, ty.distributor_id, ty.distributor_name, ty.loaded_at,
        ty.cur_year, ty.cur_period, ty.cur_week,
        
        -- 📦 DATA ORIGINAL CURRENT YEAR
        ty.target_qty AS target_qty_orig,
        ty.target_value AS target_val_orig,
        CASE WHEN ty.week <= ty.cur_week THEN ty.stm_qty ELSE 0 END AS stm_qty_orig,
        CASE WHEN ty.week <= ty.cur_week THEN ty.stm_value ELSE 0 END AS stm_val_orig,
        
        -- 🔮 DATA PROYEKSI MASA DEPAN ORIGINAL
        CASE WHEN ty.week > ty.cur_week THEN ty.salfo_qty ELSE 0 END AS est_forward_qty_orig,
        CASE WHEN ty.week > ty.cur_week THEN ty.salfo_value ELSE 0 END AS est_forward_val_orig,
        
        -- ⚙️ DATA YTD & MTD
        ty.target_qty_ytd_ty, ty.stm_qty_ytd_ty,
        ty.target_val_ytd_ty, ty.stm_val_ytd_ty,
        ty.target_qty_mtd_ty, ty.stm_qty_mtd_ty,
        ty.target_val_mtd_ty, ty.stm_val_mtd_ty,
        
        -- 📈 MOVING TREN LINIER
        ty.avg_5w_qty_raw, ty.avg_5w_val_raw,
        ty.avg_13w_qty_raw, ty.avg_13w_val_raw,
        
        -- 🟢 ATRIBUT HISTORIS TAHUN LALU (LY)
        COALESCE(ly.target_qty, 0) AS target_qty_ly_orig,
        COALESCE(ly.target_value, 0) AS target_val_ly_orig,
        COALESCE(ly.stm_qty, 0) AS stm_qty_ly_orig,
        COALESCE(ly.stm_value, 0) AS stm_val_ly_orig,
        COALESCE(ly.target_qty_ytd_ly, 0) AS target_qty_ytd_ly,
        COALESCE(ly.stm_qty_ytd_ly, 0) AS stm_qty_ytd_ly,
        COALESCE(ly.target_val_ytd_ly, 0) AS target_val_ytd_ly,
        COALESCE(ly.stm_val_ytd_ly, 0) AS stm_val_ytd_ly,
        
        -- ✨ TAMPUNGAN HELPER LOCK & RUN RATE ESTIMATION
        ty.target_qty_fy, ty.target_val_fy,
        COALESCE(ly.target_qty_fy_ly, 0) AS target_qty_fy_ly,
        COALESCE(ly.target_val_fy_ly, 0) AS target_val_fy_ly,
        
        (ty.avg_qty_per_week_ytd * ty.remaining_weeks_in_year) AS est_forward_qty_calc,
        (ty.stm_qty_ytd_ty + (ty.avg_qty_per_week_ytd * ty.remaining_weeks_in_year)) AS est_full_year_qty_calc,
        (ty.avg_val_per_week_ytd * ty.remaining_weeks_in_year) AS est_forward_val_calc,
        (ty.stm_val_ytd_ty + (ty.avg_val_per_week_ytd * ty.remaining_weeks_in_year)) AS est_full_year_val_calc,
        
        -- 🛑 DATA CLOSING BULAN LALU (Aman lintas tahun dengan pengurangan Index 1)
        COALESCE(lm.total_target_qty_closing, 0) AS target_qty_lm,
        COALESCE(lm.total_stm_qty_closing, 0) AS stm_qty_lm,
        COALESCE(lm.total_target_val_closing, 0) AS target_val_lm,
        COALESCE(lm.total_stm_val_closing, 0) AS stm_val_lm

    FROM base_ty ty
    
    -- Join 1: Menarik data Tahun Lalu (LY) per week
    LEFT JOIN base_ly ly 
      ON ty.week = ly.week
     AND ty.channel = ly.channel AND ty.parent_id = ly.parent_id AND ty.distributor_id = ly.distributor_id
     AND ty.brand_id = ly.brand_id AND ty.subbrand_id = ly.subbrand_id AND ty.flag_sku = ly.flag_sku
     
    -- Join 2: Menarik data Bulan Lalu menggunakan Single Continuous Index
    LEFT JOIN closing_period_data lm 
      ON ((ty.year * 12) + ty.period) - 1 = lm.continuous_period_id
     AND ty.channel = lm.channel AND ty.parent_id = lm.parent_id AND ty.distributor_id = lm.distributor_id
     AND ty.brand_id = lm.brand_id AND ty.subbrand_id = lm.subbrand_id AND ty.flag_sku = lm.flag_sku
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
        est_forward_qty_orig AS est_forward_original,
        
        target_qty_ly_orig AS target_original_ly,
        stm_qty_ly_orig AS stm_original_ly,
        
        target_qty_ytd_ty AS target_ytd, 
        stm_qty_ytd_ty AS stm_ytd, 
        target_qty_ytd_ly AS target_ytd_ly,
        stm_qty_ytd_ly AS stm_ytd_ly,
        
        target_qty_mtd_ty AS target_mtd, 
        stm_qty_mtd_ty AS stm_mtd,
        
        CASE WHEN week <= cur_week THEN target_qty_lm ELSE 0 END AS target_lm, 
        CASE WHEN week <= cur_week THEN stm_qty_lm ELSE 0 END AS stm_lm,
        CASE WHEN week <= cur_week THEN avg_5w_qty_raw ELSE 0 END AS avg_5w_value, 
        CASE WHEN week <= cur_week THEN avg_13w_qty_raw ELSE 0 END AS avg_13w_value,
        
        period AS min_urutan_period, 
        week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week,
        
        -- ✨ PENYEMATAN KOLOM HELPER BARU KE OUTPUT DATAMART
        target_qty_fy AS target_full_year,
        target_qty_fy_ly AS target_full_year_ly,
        est_forward_qty_calc AS est_forward_calculated,
        est_full_year_qty_calc AS est_full_year_calculated
        
    FROM horizontal_registry

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
        est_forward_val_orig AS est_forward_original,
        
        target_val_ly_orig AS target_original_ly,
        stm_val_ly_orig AS stm_original_ly,
        
        target_val_ytd_ty AS target_ytd, 
        stm_val_ytd_ty AS stm_val_ytd_ty, 
        target_val_ytd_ly AS target_ytd_ly,
        stm_val_ytd_ly AS stm_val_ytd_ly,
        
        target_val_mtd_ty AS target_mtd, 
        stm_val_mtd_ty AS stm_mtd,
        
        CASE WHEN week <= cur_week THEN target_val_lm ELSE 0 END AS target_lm, 
        CASE WHEN week <= cur_week THEN stm_val_lm ELSE 0 END AS stm_lm,
        CASE WHEN week <= cur_week THEN avg_5w_val_raw ELSE 0 END AS avg_5w_value, 
        CASE WHEN week <= cur_week THEN avg_13w_val_raw ELSE 0 END AS avg_13w_value,
        
        period AS min_urutan_period, 
        week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week,
        
        -- ✨ PENYEMATAN KOLOM HELPER BARU KE OUTPUT DATAMART
        target_val_fy AS target_full_year,
        target_val_fy_ly AS target_full_year_ly,
        est_forward_val_calc AS est_forward_calculated,
        est_full_year_val_calc AS est_full_year_calculated
        
    FROM horizontal_registry
)
SELECT * FROM unpivoted