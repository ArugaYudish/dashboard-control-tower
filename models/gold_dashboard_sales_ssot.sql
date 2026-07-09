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

all_weeks AS (
    -- 🗓️ 2. AMBIL DAFTAR MINGGU & PERIODE UNIK SECARA MATANG DARI KALENDER
    SELECT DISTINCT 
        year, period, week
    FROM spx.m_cycle3
),

unique_entities AS (
    -- 👥 3. KUNCI SELURUH EMBER HIRARKI YANG PERNAH ADA TRANSAKSI (ANTI-HILANG)
    SELECT DISTINCT 
        year, channel, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, 
        ss_id, ss_name, sbu_id, sbu_name, brand_id, brand_name, 
        subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name
    FROM spx.silver_sales_performance_parent
),

spine AS (
    -- 🦴 4. TULANG PUNGGUNG DASHBOARD: Cross Join agar setiap entitas dipastikan memiliki baris dari Week 1 s/d Akhir
    SELECT 
        w.period,
        w.week,
        e.*
    FROM unique_entities e
    JOIN all_weeks w ON e.year = w.year -- Dikunci per tahun jalurnya masing-masing
),

base_data_filled AS (
    -- 🪣 5. TEMPEL DATA SILVER KE TULANG PUNGGUNG & ISI BULANAN/MINGGUAN YANG REKAH MENJADI 0
    SELECT 
        sp.channel, sp.year, sp.period, sp.week,
        sp.nsm_id, sp.nsm_name, sp.grsm_id, sp.grsm_name, sp.rsm_id, sp.rsm_name, sp.ss_id, sp.ss_name,
        sp.sbu_id, sp.sbu_name, sp.brand_id, sp.brand_name, sp.subbrand_id, sp.subbrand_name, sp.parent_id, sp.parent_name,
        sp.flag_sku, sp.distributor_id, sp.distributor_name,
        
        -- Jika baris datanya kosong karena SS sudah tidak aktif, paksa inject angka 0 biar window function tidak putus gulungannya!
        COALESCE(s.target_qty, 0) AS target_qty,
        COALESCE(s.target_value, 0) AS target_value,
        COALESCE(s.salfo_qty, 0) AS salfo_qty,
        COALESCE(s.salfo_value, 0) AS salfo_value,
        COALESCE(s.stm_qty, 0) AS stm_qty,
        COALESCE(s.stm_value, 0) AS stm_value,
        COALESCE(s.avg_5w_qty, 0) AS avg_5w_qty,
        COALESCE(s.avg_5w_value, 0) AS avg_5w_value,
        COALESCE(s.avg_13w_qty, 0) AS avg_13w_qty,
        COALESCE(s.avg_13w_value, 0) AS avg_13w_value,
        COALESCE(s.loaded_at, NOW()) AS loaded_at
    FROM spine sp
    LEFT JOIN spx.silver_sales_performance_parent s ON sp.year = s.year 
        AND sp.week = s.week
        AND sp.distributor_id = s.distributor_id
        AND sp.brand_id = s.brand_id
        AND sp.subbrand_id = s.subbrand_id
        AND sp.ss_id = s.ss_id
        AND sp.parent_id = s.parent_id
        AND sp.flag_sku = s.flag_sku
),

base_data_ytd AS (
    -- 🌟 6. HITUNG GULUNGAN YTD & MTD (Sekarang dijamin aman karena baris data 000-nya lengkap mengalir!)
    SELECT 
        s.*,
        SUM(s.target_qty) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS target_qty_ytd,
        SUM(s.stm_qty) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS stm_qty_ytd,
        SUM(s.salfo_qty) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS salfo_qty_ytd,
        
        SUM(s.target_value) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS target_val_ytd,
        SUM(s.stm_value) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS stm_val_ytd,
        SUM(s.salfo_value) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS salfo_val_ytd,
        
        SUM(s.target_qty) OVER (PARTITION BY s.year, s.period, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS target_qty_mtd,
        SUM(s.stm_qty) OVER (PARTITION BY s.year, s.period, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS stm_qty_mtd,
        SUM(s.target_value) OVER (PARTITION BY s.year, s.period, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS target_val_mtd,
        SUM(s.stm_value) OVER (PARTITION BY s.year, s.period, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id ORDER BY s.week) AS stm_val_mtd,

        SUM(s.target_qty) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id) AS target_qty_fy_statis,
        SUM(s.target_value) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id) AS target_val_fy_statis,
        SUM(s.salfo_qty) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id) AS salfo_qty_fy_statis,
        SUM(s.salfo_value) OVER (PARTITION BY s.year, s.channel, s.sbu_id, s.grsm_id, s.rsm_id, s.ss_id, s.parent_id, s.brand_id, s.subbrand_id, s.flag_sku, s.distributor_id) AS salfo_val_fy_statis
    FROM base_data_filled s
),

join_last_year AS (
    -- 🔄 7. FULL JOIN UNTUK MATING DATA TAHUN LALU (LY) YANG SUDAH TERISI MATANG MATRIKSNYA
    SELECT 
        COALESCE(ty.year, ly.year + 1) AS year,
        COALESCE(ty.week, ly.week) AS week,
        COALESCE(ty.period, ly.period) AS period,
        COALESCE(ty.channel, ly.channel) AS channel,
        COALESCE(ty.sbu_id, ly.sbu_id) AS sbu_id,
        COALESCE(ty.sbu_name, ly.sbu_name) AS sbu_name,
        COALESCE(ty.grsm_id, ly.grsm_id) AS grsm_id,
        COALESCE(ty.grsm_name, ly.grsm_name) AS grsm_name,
        COALESCE(ty.rsm_id, ly.rsm_id) AS rsm_id,
        COALESCE(ty.rsm_name, ly.rsm_name) AS rsm_name,
        COALESCE(ty.ss_id, ly.ss_id) AS ss_id,
        COALESCE(ty.ss_name, ly.ss_name) AS ss_name,
        COALESCE(ty.nsm_id, ly.nsm_id) AS nsm_id,
        COALESCE(ty.nsm_name, ly.nsm_name) AS nsm_name,
        COALESCE(ty.parent_id, ly.parent_id) AS parent_id,
        COALESCE(ty.parent_name, ly.parent_name) AS parent_name,
        COALESCE(ty.brand_id, ly.brand_id) AS brand_id,
        COALESCE(ty.brand_name, ly.brand_name) AS brand_name,
        COALESCE(ty.subbrand_id, ly.subbrand_id) AS subbrand_id,
        COALESCE(ty.subbrand_name, ly.subbrand_name) AS subbrand_name,
        COALESCE(ty.flag_sku, ly.flag_sku) AS flag_sku,
        COALESCE(ty.distributor_id, ly.distributor_id) AS distributor_id,
        COALESCE(ty.distributor_name, ly.distributor_name) AS distributor_name,
        COALESCE(ty.loaded_at, ly.loaded_at) AS loaded_at,
        
        COALESCE(ty.salfo_qty, 0) AS salfo_qty,
        COALESCE(ty.salfo_value, 0) AS salfo_value,
        COALESCE(ty.avg_5w_qty, 0) AS avg_5w_qty,
        COALESCE(ty.avg_5w_value, 0) AS avg_5w_value,
        COALESCE(ty.avg_13w_qty, 0) AS avg_13w_qty,
        COALESCE(ty.avg_13w_value, 0) AS avg_13w_value,
        
        COALESCE(ty.target_qty_ytd, 0) AS target_qty_ytd,
        COALESCE(ty.stm_qty_ytd, 0) AS stm_qty_ytd,
        COALESCE(ty.salfo_qty_ytd, 0) AS salfo_qty_ytd,
        COALESCE(ty.target_val_ytd, 0) AS target_val_ytd,
        COALESCE(ty.stm_val_ytd, 0) AS stm_val_ytd,
        COALESCE(ty.salfo_val_ytd, 0) AS salfo_val_ytd,
        COALESCE(ty.target_qty_mtd, 0) AS target_qty_mtd,
        COALESCE(ty.stm_qty_mtd, 0) AS stm_qty_mtd,
        COALESCE(ty.target_val_mtd, 0) AS target_val_mtd,
        COALESCE(ty.stm_val_mtd, 0) AS stm_val_mtd,
        COALESCE(ty.target_qty_fy_statis, 0) AS target_qty_fy_statis,
        COALESCE(ty.target_val_fy_statis, 0) AS target_val_fy_statis,
        
        COALESCE(ly.stm_qty_ytd, 0) AS stm_qty_ytd_ly,
        COALESCE(ly.stm_val_ytd, 0) AS stm_val_ytd_ly
    FROM base_data_ytd ty
    FULL OUTER JOIN base_data_ytd ly ON (ty.year = ly.year + 1)
        AND ty.week = ly.week
        AND ty.channel = ly.channel
        AND ty.sbu_id = ly.sbu_id
        AND ty.grsm_id = ly.grsm_id
        AND ty.rsm_id = ly.rsm_id
        AND ty.ss_id = ly.ss_id
        AND ty.parent_id = ly.parent_id
        AND ty.brand_id = ly.brand_id
        AND ty.subbrand_id = ly.subbrand_id
        AND ty.flag_sku = ly.flag_sku
        AND ty.distributor_id = ly.distributor_id
),

calculated_features AS (
    SELECT 
        j.*,
        LAG(j.target_qty_mtd, 4) OVER (PARTITION BY j.year, j.channel, j.sbu_id, j.grsm_id, j.rsm_id, j.ss_id, j.parent_id, j.brand_id, j.subbrand_id, j.flag_sku, j.distributor_id ORDER BY j.week) AS target_qty_lm,
        LAG(j.stm_qty_mtd, 4) OVER (PARTITION BY j.year, j.channel, j.sbu_id, j.grsm_id, j.rsm_id, j.ss_id, j.parent_id, j.brand_id, j.subbrand_id, j.flag_sku, j.distributor_id ORDER BY j.week) AS stm_qty_lm,
        LAG(j.target_val_mtd, 4) OVER (PARTITION BY j.year, j.channel, j.sbu_id, j.grsm_id, j.rsm_id, j.ss_id, j.parent_id, j.brand_id, j.subbrand_id, j.flag_sku, j.distributor_id ORDER BY j.week) AS target_val_lm,
        LAG(j.stm_val_mtd, 4) OVER (PARTITION BY j.year, j.channel, j.sbu_id, j.grsm_id, j.rsm_id, j.ss_id, j.parent_id, j.brand_id, j.subbrand_id, j.flag_sku, j.distributor_id ORDER BY j.week) AS stm_val_lm,

        (j.target_qty_fy_statis - j.target_qty_ytd) AS target_qty_kedepan, -- ganti salfo pembagi proyeksi
        (j.target_val_fy_statis - j.target_val_ytd) AS target_val_kedepan,
        c.cur_year, c.cur_period, c.cur_week
    FROM join_last_year j
    CROSS JOIN current_operational c
),

final_projections AS (
    SELECT 
        cl.*,
        CASE WHEN cl.week > 0 THEN ((cl.stm_qty_ytd + cl.salfo_qty) / cl.week) * (52 - cl.week) ELSE 0 END AS est_stm_forward_qty,
        CASE WHEN cl.week > 0 THEN ((cl.stm_val_ytd + cl.salfo_qty) / cl.week) * (52 - cl.week) ELSE 0 END AS est_stm_forward_val
    FROM calculated_features cl
),

unpivoted AS (
    -- 🔵 UNPIVOT QTY
    SELECT 
        channel, year, period, '' AS periodname, week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        'QTY' AS pilihan_satuan,
        target_qty_ytd AS target_ytd, stm_qty_ytd AS stm_ytd, stm_qty_ytd_ly AS stm_ytd_ly,
        target_qty_mtd AS target_mtd, stm_qty_mtd AS stm_mtd,
        COALESCE(target_qty_lm, 0) AS target_lm, COALESCE(stm_qty_lm, 0) AS stm_lm,
        avg_5w_qty AS avg_5w_value, avg_13w_qty AS avg_13w_value,
        target_qty_fy_statis AS target_full_year_statis,
        (stm_qty_ytd + salfo_qty + est_stm_forward_qty) AS stm_est_fy,
        period AS min_urutan_period, week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM final_projections

    UNION ALL

    -- 🟢 UNPIVOT VALUE
    SELECT 
        channel, year, period, '' AS periodname, week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        'VALUE' AS pilihan_satuan,
        target_val_ytd AS target_ytd, stm_val_ytd AS stm_ytd, stm_val_ytd_ly AS stm_ytd_ly,
        target_val_mtd AS target_mtd, stm_val_mtd AS stm_mtd,
        COALESCE(target_val_lm, 0) AS target_lm, COALESCE(stm_val_lm, 0) AS stm_lm,
        avg_5w_value AS avg_5w_value, avg_13w_value AS avg_13w_value,
        target_val_fy_statis AS target_full_year_statis,
        (stm_val_ytd + salfo_value + est_stm_forward_val) AS stm_est_fy,
        period AS min_urutan_period, week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM final_projections
)
SELECT * FROM unpivoted
ORDER BY is_current_week DESC, year DESC, week DESC