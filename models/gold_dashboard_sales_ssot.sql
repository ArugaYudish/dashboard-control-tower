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
    -- 📉 2. KALKULASI TREN SECARA LINIER VERTIKAL (MELINTASI BATAS TAHUN AGAR AVG TIDAK KEMBAR)
    SELECT 
        s.*,
        -- Moving Average dihitung linier berurutan berdasarkan urutan kronologis tahun & minggu
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

base_ty AS (
    -- 🔵 BLOK DATA TAHUN INI (2026 - CY) BERGULUNG SECARA INTERNAL
    SELECT 
        l.*,
        SUM(l.target_qty) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS target_qty_ytd_ty,
        SUM(CASE WHEN l.week::int <= c.cur_week THEN l.stm_qty ELSE 0 END) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS stm_qty_ytd_ty,
        
        SUM(l.target_value) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS target_val_ytd_ty,
        SUM(CASE WHEN l.week::int <= c.cur_week THEN l.stm_value ELSE 0 END) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS stm_val_ytd_ty,
        
        -- MTD
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
    -- 🟢 BLOK DATA TAHUN LALU (2025 - LY) BERGULUNG SECARA INTERNAL
    SELECT 
        l.*,
        SUM(l.target_qty) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS target_qty_ytd_ly,
        SUM(l.stm_qty) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS stm_qty_ytd_ly,
        
        SUM(l.target_value) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS target_val_ytd_ly,
        SUM(l.stm_value) OVER (PARTITION BY l.year, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS stm_val_ytd_ly,
        
        -- MTD (Untuk keperluan Ach LM cross-year)
        SUM(l.target_qty) OVER (PARTITION BY l.year, l.period, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS target_qty_mtd_ly,
        SUM(l.stm_qty) OVER (PARTITION BY l.year, l.period, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS stm_qty_mtd_ly,
        
        SUM(l.target_value) OVER (PARTITION BY l.year, l.period, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS target_val_mtd_ly,
        SUM(l.stm_value) OVER (PARTITION BY l.year, l.period, l.channel, l.sbu_id, l.grsm_id, l.rsm_id, l.ss_id, l.parent_id, l.brand_id, l.subbrand_id, l.flag_sku, l.distributor_id ORDER BY l.week::int) AS stm_val_mtd_ly
    FROM linear_time_spine l
    CROSS JOIN current_operational c
    WHERE l.year::int = (c.cur_year - 1)
),

horizontal_registry AS (
    -- 🗜️ 3. JOIN HORIZONTAL MUTLAK BERDASARKAN DIMENSI DAN WEEK
    SELECT 
        ty.year, ty.period, ty.periodname, ty.week,
        ty.channel, ty.nsm_id, ty.nsm_name, ty.grsm_id, ty.grsm_name, ty.rsm_id, ty.rsm_name, ty.ss_id, ty.ss_name,
        ty.sbu_id, ty.sbu_name, ty.brand_id, ty.brand_name, ty.subbrand_id, ty.subbrand_name, ty.parent_id, ty.parent_name,
        ty.flag_sku, ty.distributor_id, ty.distributor_name, ty.loaded_at,
        ty.cur_year, ty.cur_period, ty.cur_week,
        
        -- 📦 DATA ORIGINAL CURRENT YEAR (Jika week di masa depan, STM diganti SALFO)
        ty.target_qty AS target_qty_orig,
        ty.target_value AS target_val_orig,
        
        CASE WHEN ty.week::int <= ty.cur_week THEN ty.stm_qty ELSE 0 END AS stm_qty_orig,
        CASE WHEN ty.week::int <= ty.cur_week THEN ty.stm_value ELSE 0 END AS stm_val_orig,
        
        CASE WHEN ty.week::int <= ty.cur_week THEN ty.salfo_qty ELSE 0 END AS salfo_qty_orig,
        CASE WHEN ty.week::int <= ty.cur_week THEN ty.salfo_value ELSE 0 END AS salfo_val_orig,
        
        -- 🔮 ESTIMASI PENGGANTI (Jika masa depan, ambil SALFO asli buat isi kekosongan STM)
        CASE WHEN ty.week::int > ty.cur_week THEN ty.salfo_qty ELSE 0 END AS est_forward_qty_orig,
        CASE WHEN ty.week::int > ty.cur_week THEN ty.salfo_value ELSE 0 END AS est_forward_val_orig,
        
        -- ⚙️ DATA YTD & MTD CURRENT YEAR
        ty.target_qty_ytd_ty, ty.stm_qty_ytd_ty,
        ty.target_val_ytd_ty, ty.stm_val_ytd_ty,
        ty.target_qty_mtd_ty, ty.stm_qty_mtd_ty,
        ty.target_val_mtd_ty, ty.stm_val_mtd_ty,
        
        -- 📈 DATA MOVING AVERAGE LINIER (Anti-Kembar)
        ty.avg_5w_qty_raw, ty.avg_5w_val_raw,
        ty.avg_13w_qty_raw, ty.avg_13w_val_raw,
        
        -- 🟢 ATRIBUT HISTORIS TAHUN LALU (Menempel horizontal di baris CY)
        COALESCE(ly.target_qty, 0) AS target_qty_ly_orig,
        COALESCE(ly.target_value, 0) AS target_val_ly_orig,
        COALESCE(ly.stm_qty, 0) AS stm_qty_ly_orig,
        COALESCE(ly.stm_value, 0) AS stm_val_ly_orig,
        
        COALESCE(ly.target_qty_ytd_ly, 0) AS target_qty_ytd_ly,
        COALESCE(ly.stm_qty_ytd_ly, 0) AS stm_qty_ytd_ly,
        COALESCE(ly.target_val_ytd_ly, 0) AS target_val_ytd_ly,
        COALESCE(ly.stm_val_ytd_ly, 0) AS stm_val_ytd_ly,
        
        -- Data MTD Tahun lalu ditempel buat pengaman LAG di Period 1
        COALESCE(ly.target_qty_mtd_ly, 0) AS target_qty_mtd_ly,
        COALESCE(ly.stm_qty_mtd_ly, 0) AS stm_qty_mtd_ly,
        COALESCE(ly.target_val_mtd_ly, 0) AS target_val_mtd_ly,
        COALESCE(ly.stm_val_mtd_ly, 0) AS stm_val_mtd_ly
    FROM base_ty ty
    LEFT JOIN base_ly ly 
      ON ty.week::int = ly.week::int 
     AND ty.channel = ly.channel 
     AND ty.parent_id = ly.parent_id 
     AND ty.distributor_id = ly.distributor_id
     AND ty.brand_id = ly.brand_id
     AND ty.subbrand_id = ly.subbrand_id
     AND ty.flag_sku = ly.flag_sku
),

calculated_features AS (
    -- 🕵️‍♂️ 4. PROSES LAG BULAN LALU (LAST MONTH) BERBASIS BARIS HORIZONTAL 2026
    SELECT 
        hr.*,
        -- Normal LAG untuk week > 4 (Masih di tahun 2026)
        LAG(hr.target_qty_mtd_ty, 4) OVER (PARTITION BY hr.year, hr.channel, hr.sbu_id, hr.grsm_id, hr.rsm_id, hr.ss_id, hr.parent_id, hr.brand_id, hr.subbrand_id, hr.flag_sku, hr.distributor_id ORDER BY hr.week::int) AS target_qty_lm_internal,
        LAG(hr.stm_qty_mtd_ty, 4) OVER (PARTITION BY hr.year, hr.channel, hr.sbu_id, hr.grsm_id, hr.rsm_id, hr.ss_id, hr.parent_id, hr.brand_id, hr.subbrand_id, hr.flag_sku, hr.distributor_id ORDER BY hr.week::int) AS stm_qty_lm_internal,
        LAG(hr.target_val_mtd_ty, 4) OVER (PARTITION BY hr.year, hr.channel, hr.sbu_id, hr.grsm_id, hr.rsm_id, hr.ss_id, hr.parent_id, hr.brand_id, hr.subbrand_id, hr.flag_sku, hr.distributor_id ORDER BY hr.week::int) AS target_val_lm_internal,
        LAG(hr.stm_val_mtd_ty, 4) OVER (PARTITION BY hr.year, hr.channel, hr.sbu_id, hr.grsm_id, hr.rsm_id, hr.ss_id, hr.parent_id, hr.brand_id, hr.subbrand_id, hr.flag_sku, hr.distributor_id ORDER BY hr.week::int) AS stm_val_lm_internal
    FROM horizontal_registry hr
),

final_handled_data AS (
    -- 🛡️ 5. INTERCEPT KHUSUS UNTUK MENANGANI WEEK AWAL (PERIOD 1 2026 NAMBAK KE DESEMBER 2025 HORIZONTAL)
    SELECT 
        cf.*,
        -- Jika week <= 4 (Period 1), ambil data MTD milik tahun lalu di week yang bersesuaian (Week 49-52 tahun lalu)
        CASE WHEN cf.week::int <= 4 THEN cf.target_qty_mtd_ly ELSE COALESCE(cf.target_qty_lm_internal, 0) END AS target_qty_lm,
        CASE WHEN cf.week::int <= 4 THEN cf.stm_qty_mtd_ly ELSE COALESCE(cf.stm_qty_lm_internal, 0) END AS stm_qty_lm,
        CASE WHEN cf.week::int <= 4 THEN cf.target_val_mtd_ly ELSE COALESCE(cf.target_val_lm_internal, 0) END AS target_val_lm,
        CASE WHEN cf.week::int <= 4 THEN cf.stm_val_mtd_ly ELSE COALESCE(cf.stm_val_lm_internal, 0) END AS stm_val_lm
    FROM calculated_features cf
),

unpivoted AS (
    -- 🔵 UNPIVOT QTY
    SELECT 
        channel, year, period, periodname, week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        
        'QTY' AS pilihan_satuan,
        
        -- Ember Data Original Mingguan (Murni Tanpa Gulungan)
        target_qty_orig AS target_original,
        stm_qty_orig AS stm_original,
        salfo_qty_orig AS salfo_original,
        est_forward_qty_orig AS est_forward_original,
        
        target_qty_ly_orig AS target_original_ly,
        stm_qty_ly_orig AS stm_original_ly,
        
        -- Ember Data Kalkulasi Dashboard (Kunci 0 jika melompati kalender operasional riil)
        target_qty_ytd_ty AS target_ytd, 
        stm_qty_ytd_ty AS stm_ytd, 
        target_qty_ytd_ly AS target_ytd_ly,
        stm_qty_ytd_ly AS stm_ytd_ly,
        
        target_qty_mtd_ty AS target_mtd, 
        stm_qty_mtd_ty AS stm_mtd,
        
        CASE WHEN week::int <= cur_week THEN COALESCE(target_qty_lm, 0) ELSE 0 END AS target_lm, 
        CASE WHEN week::int <= cur_week THEN COALESCE(stm_qty_lm, 0) ELSE 0 END AS stm_lm,
        CASE WHEN week::int <= cur_week THEN avg_5w_qty_raw ELSE 0 END AS avg_5w_value, 
        CASE WHEN week::int <= cur_week THEN avg_13w_qty_raw ELSE 0 END AS avg_13w_value,
        
        period AS min_urutan_period, 
        week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM final_handled_data

    UNION ALL

    -- 🟢 UNPIVOT VALUE
    SELECT 
        channel, year, period, periodname, week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        
        'VALUE' AS pilihan_satuan,
        
        -- Ember Data Original Mingguan (Murni Tanpa Gulungan)
        target_val_orig AS target_original,
        stm_val_orig AS stm_original,
        salfo_val_orig AS salfo_original,
        est_forward_val_orig AS est_forward_original,
        
        target_val_ly_orig AS target_original_ly,
        stm_val_ly_orig AS stm_original_ly,
        
        -- Ember Data Kalkulasi Dashboard (Kunci 0 jika melompati kalender operasional riil)
        target_val_ytd_ty AS target_ytd, 
        stm_val_ytd_ty AS stm_ytd, 
        target_val_ytd_ly AS target_ytd_ly,
        stm_val_ytd_ly AS stm_ytd_ly,
        
        target_val_mtd_ty AS target_mtd, 
        stm_val_mtd_ty AS stm_mtd,
        
        CASE WHEN week::int <= cur_week THEN COALESCE(target_val_lm, 0) ELSE 0 END AS target_lm, 
        CASE WHEN week::int <= cur_week THEN COALESCE(stm_val_lm, 0) ELSE 0 END AS stm_lm,
        CASE WHEN week::int <= cur_week THEN avg_5w_val_raw ELSE 0 END AS avg_5w_value, 
        CASE WHEN week::int <= cur_week THEN avg_13w_val_raw ELSE 0 END AS avg_13w_value,
        
        period AS min_urutan_period, 
        week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM final_handled_data
)
SELECT * FROM unpivoted