{{ config(
    materialized='table',
    alias='gold_dashboard_sales_ssot',
    indexes=[
      {'columns': ['year', 'period', 'week', 'pilihan_satuan', 'channel', 'parent_id', 'distributor_id', 'grsm_id', 'rsm_id']}
    ]
) }}

WITH current_operational AS (
    -- 📅 1. KUNCIAN UTAMA KALENDER REAL OPERASIONAL MAYORA (Sesuai m_cycle3)
    SELECT 
        year::text AS cur_year,
        period::text AS cur_period,
        week::numeric AS cur_week
    FROM spx.m_cycle3 
    WHERE cdate::date = CURRENT_DATE
    LIMIT 1
),

base_data AS (
    SELECT 
        s.*,
        -- =========================================================================
        -- 🌟 2. YTD ACCUMULATION (AKUMULASI HISTORIS MARKET DARI W1 S/D WEEK BERJALAN)
        -- =========================================================================
        SUM(s.target_qty) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week::numeric) AS target_qty_ytd,
        SUM(s.stm_qty) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week::numeric) AS stm_qty_ytd,
        SUM(s.salfo_qty) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week::numeric) AS salfo_qty_ytd,
        
        SUM(s.target_value) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week::numeric) AS target_val_ytd,
        SUM(s.stm_value) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week::numeric) AS stm_val_ytd,
        SUM(s.salfo_value) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week::numeric) AS salfo_val_ytd,
        
        -- =========================================================================
        -- 🌟 3. MTD ACCUMULATION (RESET TIAP BERGANTI PERIOD/BULAN)
        -- =========================================================================
        SUM(s.target_qty) OVER (PARTITION BY s.year, s.period, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week::numeric) AS target_qty_mtd,
        SUM(s.stm_qty) OVER (PARTITION BY s.year, s.period, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week::numeric) AS stm_qty_mtd,
        SUM(s.target_value) OVER (PARTITION BY s.year, s.period, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week::numeric) AS target_val_mtd,
        SUM(s.stm_value) OVER (PARTITION BY s.year, s.period, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week::numeric) AS stm_val_mtd,

        -- =========================================================================
        -- 🌟 4. GULUNG MENTOK TAHUNAN W1-W52 (TOTAL TARGET & FORECAST)
        -- =========================================================================
        SUM(s.target_qty) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id) AS target_qty_fy_statis,
        SUM(s.target_value) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id) AS target_val_fy_statis,
        
        SUM(s.salfo_qty) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id) AS salfo_qty_fy_statis,
        SUM(s.salfo_value) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id) AS salfo_val_fy_statis
        
    FROM spx.silver_sales_performance_parent s
    WHERE s.week IS NOT NULL
),

calculated_features AS (
    SELECT 
        b.*,
        -- 5. Ambil data Last Month (LM) mundur 4 minggu untuk performance market
        LAG(b.target_qty_mtd, 4) OVER (PARTITION BY b.year, b.channel, b.sbu_id, b.grsm_id, b.rsm_id, b.ss_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku, b.distributor_id ORDER BY b.week::numeric) AS target_qty_lm,
        LAG(b.stm_qty_mtd, 4) OVER (PARTITION BY b.year, b.channel, b.sbu_id, b.grsm_id, b.rsm_id, b.ss_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku, b.distributor_id ORDER BY b.week::numeric) AS stm_qty_lm,
        LAG(b.target_val_mtd, 4) OVER (PARTITION BY b.year, b.channel, b.sbu_id, b.grsm_id, b.rsm_id, b.ss_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku, b.distributor_id ORDER BY b.week::numeric) AS target_val_lm,
        LAG(b.stm_val_mtd, 4) OVER (PARTITION BY b.year, b.channel, b.sbu_id, b.grsm_id, b.rsm_id, b.ss_id, b.parent_id, b.brand_id, b.subbrand_id, b.flag_sku, b.distributor_id ORDER BY b.week::numeric) AS stm_val_lm,

        -- 6. FORECAST KEDEPAN = TOTAL TAUNAN - YANG SUDAH JALAN KESERAP YTD
        (b.salfo_qty_fy_statis - b.salfo_qty_ytd) AS salfo_qty_kedepan,
        (b.salfo_val_fy_statis - b.salfo_val_ytd) AS salfo_val_kedepan,
        
        -- Inject kuncian kalender operasional hari ini via cross join
        c.cur_year, c.cur_period, c.cur_week
    FROM base_data b
    CROSS JOIN current_operational c
),

final_projections AS (
    SELECT 
        cl.*,
        -- 7. EKSEKUSI RUMUS SAKLEK: ((STM YTD + SALFO KEDEPAN) / CURRENT WEEK) * SISA WEEK
        CASE 
            WHEN cl.week::numeric > 0 THEN ((cl.stm_qty_ytd + cl.salfo_qty_kedepan) / cl.week::numeric) * (52 - cl.week::numeric)
            ELSE 0 
        END AS est_stm_forward_qty,
        
        CASE 
            WHEN cl.week::numeric > 0 THEN ((cl.stm_val_ytd + cl.salfo_val_kedepan) / cl.week::numeric) * (52 - cl.week::numeric)
            ELSE 0 
        END AS est_stm_forward_val
    FROM calculated_features cl
),

unpivoted AS (
    -- 🔵 UNPIVOT DATA QUANTITY (QTY)
    SELECT 
        channel, year, period, periodname, week::numeric AS week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        
        'QTY' AS pilihan_satuan,
        
        target_qty_ytd AS target_ytd, 
        stm_qty_ytd AS stm_ytd,
        0::numeric AS stm_ytd_ly,
        
        target_qty_mtd AS target_mtd, 
        stm_qty_mtd AS stm_mtd,
        
        COALESCE(target_qty_lm, 0) AS target_lm, 
        COALESCE(stm_qty_lm, 0) AS stm_lm,
        
        avg_5w_qty AS avg_5w_value, 
        avg_13w_qty AS avg_13w_value,
        
        target_qty_fy_statis AS target_full_year_statis,
        (stm_qty_ytd + salfo_qty + est_stm_forward_qty) AS stm_est_fy,
        
        -- Atribut Helper untuk UI Filter & Default Selection Superset
        (period::numeric) AS min_urutan_period,
        (week::numeric) AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
        
    FROM final_projections

    UNION ALL

    -- 🟢 UNPIVOT DATA VALUE
    SELECT 
        channel, year, period, periodname, week::numeric AS week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        
        'VALUE' AS pilihan_satuan,
        
        target_val_ytd AS target_ytd, 
        stm_val_ytd AS stm_ytd,
        0::numeric AS stm_ytd_ly,
        
        target_val_mtd AS target_mtd, 
        stm_val_mtd AS stm_mtd,
        
        COALESCE(target_val_lm, 0) AS target_lm, 
        COALESCE(stm_val_lm, 0) AS stm_lm,
        
        avg_5w_value AS avg_5w_value, 
        avg_13w_value AS avg_13w_value,
        
        target_val_fy_statis AS target_full_year_statis,
        (stm_val_ytd + salfo_value + est_stm_forward_val) AS stm_est_fy,
        
        -- Atribut Helper untuk UI Filter & Default Selection Superset
        (period::numeric) AS min_urutan_period,
        (week::numeric) AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
        
    FROM final_projections
)
SELECT * FROM unpivoted
-- Pengondisian sortir agar baris minggu berjalan hari ini nangkring paling atas secara default
ORDER BY is_current_week DESC, year DESC, week DESC