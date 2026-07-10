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

base_spine AS (
    -- 🗜️ 2. TARIK DATA SILVER UTUH
    SELECT 
        s.*,
        c.cur_year, c.cur_period, c.cur_week
    FROM spx.silver_sales_performance_parent s
    CROSS JOIN current_operational c
    WHERE s.year::int IN (c.cur_year, c.cur_year - 1) AND s.week IS NOT NULL
),

monthly_aggregates AS (
    -- 🛑 3. CTE RANGKUMAN BULANAN (UNTUK DI-SHIFT MUNDUR 1 BULAN HORIZONTAL)
    -- Di-group per periode untuk mengunci total jualan 1 bulan penuh (Anti-bocor 4 week vs 5 week)
    SELECT 
        year::int AS agg_year,
        period::int AS agg_period,
        channel, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name,
        SUM(target_qty) AS total_target_qty_monthly,
        SUM(CASE WHEN year = 2026 AND week <= (SELECT cur_week FROM current_operational) THEN stm_qty WHEN year < 2026 THEN stm_qty ELSE 0 END) AS total_stm_qty_monthly,
        SUM(target_value) AS total_target_val_monthly,
        SUM(CASE WHEN year = 2026 AND week <= (SELECT cur_week FROM current_operational) THEN stm_value WHEN year < 2026 THEN stm_value ELSE 0 END) AS total_stm_val_monthly
    FROM spx.silver_sales_performance_parent
    WHERE week IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22
),

horizontal_registry AS (
    -- 🗜️ 4. PROPAGASI DATA BULAN LALU KE MINGGU PERTAMA BULAN BERJALAN
    SELECT 
        b.*,
        -- Kita tandai week pertama di setiap periode berjalan secara dinamis
        ROW_NUMBER() OVER (PARTITION BY b.year, b.period, b.channel, b.distributor_id, b.flag_sku ORDER BY b.week::int) AS urutan_week_dalam_bulan,

        -- Ambil data bulan lalu (Relasi: period berjalan = agg_period + 1)
        COALESCE(lm_internal.total_target_qty_monthly, lm_cross.total_target_qty_monthly, 0) AS target_qty_lm_raw,
        COALESCE(lm_internal.total_stm_qty_monthly, lm_cross.total_stm_qty_monthly, 0) AS stm_qty_lm_raw,
        COALESCE(lm_internal.total_target_val_monthly, lm_cross.total_target_val_monthly, 0) AS target_val_lm_raw,
        COALESCE(lm_internal.total_stm_val_monthly, lm_cross.total_stm_val_monthly, 0) AS stm_val_lm_raw
    FROM base_spine b
    
    -- Join internal tahun berjalan (Contoh: Data Period 2 akan mengambil summary Period 1)
    LEFT JOIN monthly_aggregates lm_internal
      ON b.year::int = lm_internal.agg_year
     AND b.period::int = lm_internal.agg_period + 1
     AND b.channel = lm_internal.channel AND b.distributor_id = lm_internal.distributor_id AND b.flag_sku = lm_internal.flag_sku
     
    -- Join transisi tahun baru (Contoh: Data Period 1 2026 akan mengambil summary Period 12 2025)
    LEFT JOIN monthly_aggregates lm_cross
      ON (b.year::int - 1) = lm_cross.agg_year
     AND b.period::int = 1 AND lm_cross.agg_period = 12
     AND b.channel = lm_cross.channel AND b.distributor_id = lm_cross.distributor_id AND b.flag_sku = lm_cross.flag_sku
),

unpivoted AS (
    -- 🔵 UNPIVOT QTY
    SELECT 
        channel, year, period, periodname, week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        'QTY' AS pilihan_satuan,
        
        target_qty AS target_original,
        CASE WHEN year = cur_year AND week <= cur_week THEN stm_qty WHEN year < cur_year THEN stm_qty ELSE 0 END AS stm_original,
        CASE WHEN year = cur_year AND week > cur_week THEN salfo_qty ELSE 0 END AS est_forward_original,
        
        -- Kuncian Utama: Masukkan angka full satu bulan lalu HANYA di baris minggu pertama bulan berjalan
        CASE WHEN urutan_week_dalam_bulan = 1 THEN target_qty_lm_raw ELSE 0 END AS target_lm,
        CASE WHEN urutan_week_dalam_bulan = 1 THEN stm_qty_lm_raw ELSE 0 END AS stm_lm,
        
        -- Masukkan Seluruh Kolom Inventory & Stock Bawaan Silver Utuh
        stock_qty, stock_value, stock_ibn, stock_ibn_value, fdos_update, fdos_value, sta_qty, sta_value,
        avg_5w_qty AS avg_5w_value, avg_13w_qty AS avg_13w_value,
        
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
        
        target_value AS target_original,
        CASE WHEN year = cur_year AND week <= cur_week THEN stm_value WHEN year < cur_year THEN stm_value ELSE 0 END AS stm_original,
        CASE WHEN year = cur_year AND week > cur_week THEN salfo_value ELSE 0 END AS est_forward_original,
        
        -- Kuncian Utama Value
        CASE WHEN urutan_week_dalam_bulan = 1 THEN target_val_lm_raw ELSE 0 END AS target_lm,
        CASE WHEN urutan_week_dalam_bulan = 1 THEN stm_val_lm_raw ELSE 0 END AS stm_lm,
        
        -- Masukkan Seluruh Kolom Inventory & Stock Bawaan Silver Utuh
        stock_qty, stock_value, stock_ibn, stock_ibn_value, fdos_update, fdos_value, sta_qty, sta_value,
        avg_5w_value AS avg_5w_value, avg_13w_value AS avg_13w_value,
        
        period AS min_urutan_period, week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM horizontal_registry
)
SELECT * FROM unpivoted