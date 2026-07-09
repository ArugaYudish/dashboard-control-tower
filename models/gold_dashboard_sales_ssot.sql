{{ config(
    materialized='table',
    alias='gold_dashboard_sales_ssot',
    indexes=[
      {'columns': ['year', 'period', 'week', 'pilihan_satuan', 'channel', 'parent_id', 'distributor_id', 'rsm_id']}
    ]
) }}

WITH base_data AS (
    SELECT 
        s.*,
        -- 1. Akumulasi Window YTD (Gulungan akumulatif dari Week 1 s/d Week berjalan)
        SUM(s.target_qty) OVER (PARTITION BY s.year, s.channel, s.parent_id, s.distributor_id, s.ss_id ORDER BY s.week::numeric) AS target_qty_ytd,
        SUM(s.stm_qty) OVER (PARTITION BY s.year, s.channel, s.parent_id, s.distributor_id, s.ss_id ORDER BY s.week::numeric) AS stm_qty_ytd,
        SUM(s.target_value) OVER (PARTITION BY s.year, s.channel, s.parent_id, s.distributor_id, s.ss_id ORDER BY s.week::numeric) AS target_val_ytd,
        SUM(s.stm_value) OVER (PARTITION BY s.year, s.channel, s.parent_id, s.distributor_id, s.ss_id ORDER BY s.week::numeric) AS stm_val_ytd,
        
        -- 2. Akumulasi Window MTD (Gulungan di dalam koridor period bulan yang sama saja)
        SUM(s.target_qty) OVER (PARTITION BY s.year, s.period, s.channel, s.parent_id, s.distributor_id, s.ss_id ORDER BY s.week::numeric) AS target_qty_mtd,
        SUM(s.stm_qty) OVER (PARTITION BY s.year, s.period, s.channel, s.parent_id, s.distributor_id, s.ss_id ORDER BY s.week::numeric) AS stm_qty_mtd,
        SUM(s.target_value) OVER (PARTITION BY s.year, s.period, s.channel, s.parent_id, s.distributor_id, s.ss_id ORDER BY s.week::numeric) AS target_val_mtd,
        SUM(s.stm_value) OVER (PARTITION BY s.year, s.period, s.channel, s.parent_id, s.distributor_id, s.ss_id ORDER BY s.week::numeric) AS stm_val_mtd,

        -- 3. Total Target Setahun Penuh Statis (Helper untuk hitung Estimasi Achievement)
        SUM(s.target_qty) OVER (PARTITION BY s.year, s.channel, s.parent_id, s.distributor_id, s.ss_id) AS target_qty_fy_statis,
        SUM(s.target_value) OVER (PARTITION BY s.year, s.channel, s.parent_id, s.distributor_id, s.ss_id) AS target_val_fy_statis
    FROM spx.silver_sales_performance_parent s
    WHERE s.week IS NOT NULL
),

unpivoted AS (
    -- 🔵 1. BLOK DATA QUANTITY (QTY)
    SELECT 
        channel, year, period, periodname, week::numeric AS week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, NOW() AS loaded_at,
        
        'QTY' AS pilihan_satuan,
        target_qty AS target_weekly, stm_qty AS stm_weekly,
        target_qty_ytd AS target_ytd, stm_qty_ytd AS stm_ytd,
        target_qty_mtd AS target_mtd, stm_qty_mtd AS stm_mtd,
        
        -- Ambil data Last Month (LM) menggunakan fungsi LAG 4 minggu ke belakang
        LAG(target_qty_mtd, 4) OVER (PARTITION BY year, channel, parent_id, distributor_id ORDER BY week) AS target_lm,
        LAG(stm_qty_mtd, 4) OVER (PARTITION BY year, channel, parent_id, distributor_id ORDER BY week) AS stm_lm,
        
        avg_5w_qty AS avg_5w_value, avg_13w_qty AS avg_13w_value,
        0::numeric AS stm_ytd_ly, -- Dummy placeholder LY karena absen di Silver skema
        
        -- Formula Proyeksi Estimasi Akhir Tahun (STM YTD / week berjalan * 52)
        CASE WHEN week > 0 THEN (stm_qty_ytd / week) * 52 ELSE 0 END AS stm_est_fy,
        target_qty_fy_statis AS target_full_year_statis
    FROM base_data

    UNION ALL

    -- 🟢 2. BLOK DATA VALUE
    SELECT 
        channel, year, period, periodname, week::numeric AS week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, NOW() AS loaded_at,
        
        'VALUE' AS pilihan_satuan,
        target_value AS target_weekly, stm_value AS stm_weekly,
        target_val_ytd AS target_ytd, stm_val_ytd AS stm_ytd,
        target_val_mtd AS target_mtd, stm_val_mtd AS stm_mtd,
        
        LAG(target_val_mtd, 4) OVER (PARTITION BY year, channel, parent_id, distributor_id ORDER BY week) AS target_lm,
        LAG(stm_val_mtd, 4) OVER (PARTITION BY year, channel, parent_id, distributor_id ORDER BY week) AS stm_lm,
        
        avg_5w_value, avg_13w_value,
        0::numeric AS stm_ytd_ly,
        
        CASE WHEN week > 0 THEN (stm_val_ytd / week) * 52 ELSE 0 END AS stm_est_fy,
        target_val_fy_statis AS target_full_year_statis
    FROM base_data
)
SELECT * FROM unpivoted