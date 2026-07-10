{{ config(
    materialized='table',
    alias='gold_dashboard_sales_ssot',
    indexes=[
      {'columns': ['year', 'period', 'week', 'pilihan_satuan', 'channel', 'parent_id', 'distributor_id', 'grsm_id', 'rsm_id']}
    ]
) }}

WITH current_operational AS (
    -- 📅 1. ANCHOR WAKTU OPERASIONAL HARI INI
    SELECT 
        year::int AS cur_year,
        period::int AS cur_period,
        week::int AS cur_week
    FROM spx.m_cycle3 
    WHERE cdate::date = CURRENT_DATE
    LIMIT 1
),

silver_ty AS (
    -- 🔵 AMBIL DATA TAHUN INI (CURRENT YEAR)
    SELECT 
        s.*,
        c.cur_year, c.cur_period, c.cur_week
    FROM spx.silver_sales_performance_parent s
    CROSS JOIN current_operational c
    WHERE s.year::int = c.cur_year AND s.week IS NOT NULL
),

silver_ly AS (
    -- 🟢 AMBIL DATA TAHUN LALU (LAST YEAR = CURRENT YEAR - 1)
    SELECT 
        s.year AS ly_year, s.period AS ly_period, s.week AS ly_week,
        s.channel, s.parent_id, s.distributor_id, s.brand_id, s.subbrand_id, s.flag_sku,
        s.stm_qty AS stm_qty_ly_raw,
        s.stm_value AS stm_val_ly_raw
    FROM spx.silver_sales_performance_parent s
    CROSS JOIN current_operational c
    WHERE s.year::int = (c.cur_year - 1) AND s.week IS NOT NULL
),

horizontal_base AS (
    -- 🗜️ 2. JOIN HORIZONTAL UNTUK MERAPATKAN SUMBU TY & LY PER WEEK
    SELECT 
        ty.year, ty.period, ty.periodname, ty.week,
        ty.channel, ty.nsm_id, ty.nsm_name, ty.grsm_id, ty.grsm_name, ty.rsm_id, ty.rsm_name, ty.ss_id, ty.ss_name,
        ty.sbu_id, ty.sbu_name, ty.brand_id, ty.brand_name, ty.subbrand_id, ty.subbrand_name, ty.parent_id, ty.parent_name,
        ty.flag_sku, ty.distributor_id, ty.distributor_name, ty.loaded_at,
        ty.cur_year, ty.cur_period, ty.cur_week,
        
        -- 🔒 DATA MENTAH ORIGINAL (Jika week > week operasional, STM & SALFO dipaksa 0!)
        ty.target_qty AS target_qty_orig,
        CASE WHEN ty.week <= ty.cur_week THEN ty.stm_qty ELSE 0 END AS stm_qty_orig,
        CASE WHEN ty.week <= ty.cur_week THEN ty.salfo_qty ELSE 0 END AS salfo_qty_orig,
        
        ty.target_value AS target_val_orig,
        CASE WHEN ty.week <= ty.cur_week THEN ty.stm_value ELSE 0 END AS stm_val_orig,
        CASE WHEN ty.week <= ty.cur_week THEN ty.salfo_value ELSE 0 END AS salfo_val_orig,
        
        -- Data historical tahun lalu langsung nempel manis di samping
        COALESCE(ly.stm_qty_ly_raw, 0) AS stm_qty_ly_ly_raw,
        COALESCE(ly.stm_val_ly_raw, 0) AS stm_val_ly_ly_raw
    FROM silver_ty ty
    LEFT JOIN silver_ly ly 
      ON ty.week = ly.ly_week 
     AND ty.channel = ly.channel 
     AND ty.parent_id = ly.parent_id 
     AND ty.distributor_id = ly.distributor_id
     AND ty.brand_id = ly.brand_id
     AND ty.subbrand_id = ly.subbrand_id
     AND ty.flag_sku = ly.flag_sku
),

base_data_ytd AS (
    -- 🌟 3. PROSES GULUNGAN YTD & MTD (Hanya bergulung sampai week aktif operasional)
    SELECT 
        hb.*,
        -- Qty YTD & MTD
        SUM(hb.target_qty_orig) OVER (PARTITION BY hb.year, hb.channel, hb.sbu_id, hb.grsm_id, hb.rsm_id, hb.ss_id, hb.parent_id, hb.brand_id, hb.subbrand_id, hb.flag_sku, hb.distributor_id ORDER BY hb.week) AS target_qty_ytd,
        SUM(hb.stm_qty_orig) OVER (PARTITION BY hb.year, hb.channel, hb.sbu_id, hb.grsm_id, hb.rsm_id, hb.ss_id, hb.parent_id, hb.brand_id, hb.subbrand_id, hb.flag_sku, hb.distributor_id ORDER BY hb.week) AS stm_qty_ytd,
        SUM(hb.stm_qty_ly_ly_raw) OVER (PARTITION BY hb.year, hb.channel, hb.sbu_id, hb.grsm_id, hb.rsm_id, hb.ss_id, hb.parent_id, hb.brand_id, hb.subbrand_id, hb.flag_sku, hb.distributor_id ORDER BY hb.week) AS stm_qty_ytd_ly,
        
        SUM(hb.target_qty_orig) OVER (PARTITION BY hb.year, hb.period, hb.channel, hb.sbu_id, hb.grsm_id, hb.rsm_id, hb.ss_id, hb.parent_id, hb.brand_id, hb.subbrand_id, hb.flag_sku, hb.distributor_id ORDER BY hb.week) AS target_qty_mtd,
        SUM(hb.stm_qty_orig) OVER (PARTITION BY hb.year, hb.period, hb.channel, hb.sbu_id, hb.grsm_id, hb.rsm_id, hb.ss_id, hb.parent_id, hb.brand_id, hb.subbrand_id, hb.flag_sku, hb.distributor_id ORDER BY hb.week) AS stm_qty_mtd,

        -- Value YTD & MTD
        SUM(hb.target_val_orig) OVER (PARTITION BY hb.year, hb.channel, hb.sbu_id, hb.grsm_id, hb.rsm_id, hb.ss_id, hb.parent_id, hb.brand_id, hb.subbrand_id, hb.flag_sku, hb.distributor_id ORDER BY hb.week) AS target_val_ytd,
        SUM(hb.stm_val_orig) OVER (PARTITION BY hb.year, hb.channel, hb.sbu_id, hb.grsm_id, hb.rsm_id, hb.ss_id, hb.parent_id, hb.brand_id, hb.subbrand_id, hb.flag_sku, hb.distributor_id ORDER BY hb.week) AS stm_val_ytd,
        SUM(hb.stm_val_ly_ly_raw) OVER (PARTITION BY hb.year, hb.channel, hb.sbu_id, hb.grsm_id, hb.rsm_id, hb.ss_id, hb.parent_id, hb.brand_id, hb.subbrand_id, hb.flag_sku, hb.distributor_id ORDER BY hb.week) AS stm_val_ytd_ly,
        
        SUM(hb.target_val_orig) OVER (PARTITION BY hb.year, hb.period, hb.channel, hb.sbu_id, hb.grsm_id, hb.rsm_id, hb.ss_id, hb.parent_id, hb.brand_id, hb.subbrand_id, hb.flag_sku, hb.distributor_id ORDER BY hb.week) AS target_val_mtd,
        SUM(hb.stm_val_orig) OVER (PARTITION BY hb.year, hb.period, hb.channel, hb.sbu_id, hb.grsm_id, hb.rsm_id, hb.ss_id, hb.parent_id, hb.brand_id, hb.subbrand_id, hb.flag_sku, hb.distributor_id ORDER BY hb.week) AS stm_val_mtd,

        -- Target Statis Full Year (Murni SUM dari total target_original di internal entitas)
        SUM(hb.target_qty_orig) OVER (PARTITION BY hb.year, hb.channel, hb.sbu_id, hb.grsm_id, hb.rsm_id, hb.ss_id, hb.parent_id, hb.brand_id, hb.subbrand_id, hb.flag_sku, hb.distributor_id) AS target_qty_fy_statis,
        SUM(hb.target_val_orig) OVER (PARTITION BY hb.year, hb.channel, hb.sbu_id, hb.grsm_id, hb.rsm_id, hb.ss_id, hb.parent_id, hb.brand_id, hb.subbrand_id, hb.flag_sku, hb.distributor_id) AS target_val_fy_statis
    FROM horizontal_base hb
),

calculated_features AS (
    -- 📈 4. PERHITUNGAN TREN & LAG (ANTI BOCOR MASA DEPAN & ANTI SEKAT TAHUN)
    SELECT 
        bd.*,
        -- Menggunakan LAG 4 baris untuk mengambil data Bulan Lalu (Last Month)
        LAG(bd.target_qty_mtd, 4) OVER (PARTITION BY bd.channel, bd.sbu_id, bd.grsm_id, bd.rsm_id, bd.ss_id, bd.parent_id, bd.brand_id, bd.subbrand_id, bd.flag_sku, bd.distributor_id ORDER BY bd.year, bd.week) AS target_qty_lm_raw,
        LAG(bd.stm_qty_mtd, 4) OVER (PARTITION BY bd.channel, bd.sbu_id, bd.grsm_id, bd.rsm_id, bd.ss_id, bd.parent_id, bd.brand_id, bd.subbrand_id, bd.flag_sku, bd.distributor_id ORDER BY bd.year, bd.week) AS stm_qty_lm_raw,
        LAG(bd.target_val_mtd, 4) OVER (PARTITION BY bd.channel, bd.sbu_id, bd.grsm_id, bd.rsm_id, bd.ss_id, bd.parent_id, bd.brand_id, bd.subbrand_id, bd.flag_sku, bd.distributor_id ORDER BY bd.year, bd.week) AS target_val_lm_raw,
        LAG(bd.stm_val_mtd, 4) OVER (PARTITION BY bd.channel, bd.sbu_id, bd.grsm_id, bd.rsm_id, bd.ss_id, bd.parent_id, bd.brand_id, bd.subbrand_id, bd.flag_sku, bd.distributor_id ORDER BY bd.year, bd.week) AS stm_val_lm_raw,

        -- Moving Average 5W & 13W (Dihitung dari data original mingguan)
        AVG(bd.stm_qty_orig) OVER (PARTITION BY bd.year, bd.channel, bd.sbu_id, bd.grsm_id, bd.rsm_id, bd.ss_id, bd.parent_id, bd.brand_id, bd.subbrand_id, bd.flag_sku, bd.distributor_id ORDER BY bd.week ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS avg_5w_qty_raw,
        AVG(bd.stm_val_orig) OVER (PARTITION BY bd.year, bd.channel, bd.sbu_id, bd.grsm_id, bd.rsm_id, bd.ss_id, bd.parent_id, bd.brand_id, bd.subbrand_id, bd.flag_sku, bd.distributor_id ORDER BY bd.week ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS avg_5w_val_raw,
        
        AVG(bd.stm_qty_orig) OVER (PARTITION BY bd.year, bd.channel, bd.sbu_id, bd.grsm_id, bd.rsm_id, bd.ss_id, bd.parent_id, bd.brand_id, bd.subbrand_id, bd.flag_sku, bd.distributor_id ORDER BY bd.week ROWS BETWEEN 12 PRECEDING AND CURRENT ROW) AS avg_13w_qty_raw,
        AVG(bd.stm_val_orig) OVER (PARTITION BY bd.year, bd.channel, bd.sbu_id, bd.grsm_id, bd.rsm_id, bd.ss_id, bd.parent_id, bd.brand_id, bd.subbrand_id, bd.flag_sku, bd.distributor_id ORDER BY bd.week ROWS BETWEEN 12 PRECEDING AND CURRENT ROW) AS avg_13w_val_raw
    FROM base_data_ytd bd
),

final_projections AS (
    -- 🔮 5. ESTIMASI PROYEKSI AKHIR TAHUN BERDASARKAN HARI INI
    SELECT 
        cf.*,
        -- Forward Estimate: ((YTD + Salfo) / week berjalan) * sisa minggu ke depan
        CASE WHEN cf.cur_week > 0 THEN ((cf.stm_qty_ytd + cf.salfo_qty_orig) / cf.cur_week) * (52 - cf.cur_week) ELSE 0 END AS est_stm_forward_qty,
        CASE WHEN cf.cur_week > 0 THEN ((cf.stm_val_ytd + cf.salfo_val_orig) / cf.cur_week) * (52 - cf.cur_week) ELSE 0 END AS est_stm_forward_val
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
        
        -- 📦 Ember Data Original Mingguan (Mentah Tanpa Gulungan)
        target_qty_orig AS target_original,
        stm_qty_orig AS stm_original,
        salfo_qty_orig AS salfo_original,
        est_stm_forward_qty AS est_forward_original,
        
        -- ⚙️ Ember Data Kalkulasi (Dipaksa 0 jika filter melompati minggu operasional aktif)
        target_qty_ytd AS target_ytd, 
        stm_qty_ytd AS stm_ytd, 
        stm_qty_ytd_ly AS stm_ytd_ly,
        target_qty_mtd AS target_mtd, 
        stm_qty_mtd AS stm_mtd,
        
        CASE WHEN week <= cur_week THEN COALESCE(target_qty_lm_raw, 0) ELSE 0 END AS target_lm, 
        CASE WHEN week <= cur_week THEN COALESCE(stm_qty_lm_raw, 0) ELSE 0 END AS stm_lm,
        CASE WHEN week <= cur_week THEN avg_5w_qty_raw ELSE 0 END AS avg_5w_value, 
        CASE WHEN week <= cur_week THEN avg_13w_qty_raw ELSE 0 END AS avg_13w_value,
        
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
        
        -- 📦 Ember Data Original Mingguan (Mentah Tanpa Gulungan)
        target_val_orig AS target_original,
        stm_val_orig AS stm_original,
        salfo_val_orig AS salfo_original,
        est_stm_forward_val AS est_forward_original,
        
        -- ⚙️ Ember Data Kalkulasi (Dipaksa 0 jika filter melompati minggu operasional aktif)
        target_val_ytd AS target_ytd, 
        stm_val_ytd AS stm_ytd, 
        stm_val_ytd_ly AS stm_ytd_ly,
        target_val_mtd AS target_mtd, 
        stm_val_mtd AS stm_mtd,
        
        CASE WHEN week <= cur_week THEN COALESCE(target_val_lm_raw, 0) ELSE 0 END AS target_lm, 
        CASE WHEN week <= cur_week THEN COALESCE(stm_val_lm_raw, 0) ELSE 0 END AS stm_lm,
        CASE WHEN week <= cur_week THEN avg_5w_val_raw ELSE 0 END AS avg_5w_value, 
        CASE WHEN week <= cur_week THEN avg_13w_val_raw ELSE 0 END AS avg_13w_value,
        
        target_val_fy_statis AS target_full_year_statis,
        (target_val_ytd + salfo_val_orig + est_stm_forward_val) AS stm_est_fy,
        
        period AS min_urutan_period, 
        week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM final_projections
)
SELECT * FROM unpivoted