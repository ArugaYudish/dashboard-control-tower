{{ config(
    materialized='table',
    alias='gold_dashboard_sales_ssot',
    indexes=[
      {'columns': ['year', 'period', 'week', 'pilihan_satuan', 'channel', 'parent_id', 'distributor_id', 'grsm_id', 'rsm_id']}
    ]
) }}

WITH current_operational AS (
    -- 📅 1. JANGKAR KALENDER OPERASIONAL HARI INI
    SELECT 
        year::int AS cur_year,
        period::int AS cur_period,
        week::int AS cur_week
    FROM spx.m_cycle3 
    WHERE cdate::date = CURRENT_DATE
    LIMIT 1
),

clean_base AS (
    -- 🗜️ 2. FILTER DATA VALID TAHUN BERJALAN & TAHUN LALU (TIDAK BERGANTUNG PADA STRING FLAG)
    SELECT 
        s.*,
        c.cur_year, c.cur_period, c.cur_week
    FROM spx.silver_sales_performance_parent s
    CROSS JOIN current_operational c
    WHERE s.year::int IN (c.cur_year, c.cur_year - 1) AND s.week IS NOT NULL
),

calculated_ytd_mtd AS (
    -- 🌟 3. PROSES AKUMULASI YTD DAN MTD SECARA LINIER VERTIKAL
    -- Supaya Week 1 tidak buta melihat Desember tahun lalu untuk Last Month (LM), kita sorting pakai ORDER BY year, week secara linier!
    SELECT 
        cb.*,
        -- Akumulasi Target & STM untuk YTD (Hanya berjalan sampai week aktif hari ini)
        SUM(cb.target_value) OVER (PARTITION BY cb.year, cb.channel, cb.sbu_id, cb.grsm_id, cb.rsm_id, cb.ss_id, cb.parent_id, cb.brand_id, cb.subbrand_id, cb.flag_sku, cb.distributor_id ORDER BY cb.week::int) AS target_val_ytd_calc,
        SUM(CASE WHEN cb.year::int = cb.cur_year AND cb.week::int <= cb.cur_week THEN cb.stm_value WHEN cb.year::int < cb.cur_year THEN cb.stm_value ELSE 0 END) 
            OVER (PARTITION BY cb.year, cb.channel, cb.sbu_id, cb.grsm_id, cb.rsm_id, cb.ss_id, cb.parent_id, cb.brand_id, cb.subbrand_id, cb.flag_sku, cb.distributor_id ORDER BY cb.week::int) AS stm_val_ytd_calc,
        
        SUM(cb.target_qty) OVER (PARTITION BY cb.year, cb.channel, cb.sbu_id, cb.grsm_id, cb.rsm_id, cb.ss_id, cb.parent_id, cb.brand_id, cb.subbrand_id, cb.flag_sku, cb.distributor_id ORDER BY cb.week::int) AS target_qty_ytd_calc,
        SUM(CASE WHEN cb.year::int = cb.cur_year AND cb.week::int <= cb.cur_week THEN cb.stm_qty WHEN cb.year::int < cb.cur_year THEN cb.stm_qty ELSE 0 END) 
            OVER (PARTITION BY cb.year, cb.channel, cb.sbu_id, cb.grsm_id, cb.rsm_id, cb.ss_id, cb.parent_id, cb.brand_id, cb.subbrand_id, cb.flag_sku, cb.distributor_id ORDER BY cb.week::int) AS stm_qty_ytd_calc,

        -- Akumulasi MTD Bulanan
        SUM(cb.target_value) OVER (PARTITION BY cb.year, cb.period, cb.channel, cb.sbu_id, cb.grsm_id, cb.rsm_id, cb.ss_id, cb.parent_id, cb.brand_id, cb.subbrand_id, cb.flag_sku, cb.distributor_id ORDER BY cb.week::int) AS target_val_mtd_calc,
        SUM(CASE WHEN cb.year::int = cb.cur_year AND cb.week::int <= cb.cur_week THEN cb.stm_value WHEN cb.year::int < cb.cur_year THEN cb.stm_value ELSE 0 END) 
            OVER (PARTITION BY cb.year, cb.period, cb.channel, cb.sbu_id, cb.grsm_id, cb.rsm_id, cb.ss_id, cb.parent_id, cb.brand_id, cb.subbrand_id, cb.flag_sku, cb.distributor_id ORDER BY cb.week::int) AS stm_val_mtd_calc,
            
        SUM(cb.target_qty) OVER (PARTITION BY cb.year, cb.period, cb.channel, cb.sbu_id, cb.grsm_id, cb.rsm_id, cb.ss_id, cb.parent_id, cb.brand_id, cb.subbrand_id, cb.flag_sku, cb.distributor_id ORDER BY cb.week::int) AS target_qty_mtd_calc,
        SUM(CASE WHEN cb.year::int = cb.cur_year AND cb.week::int <= cb.cur_week THEN cb.stm_qty WHEN cb.year::int < cb.cur_year THEN cb.stm_qty ELSE 0 END) 
            OVER (PARTITION BY cb.year, cb.period, cb.channel, cb.sbu_id, cb.grsm_id, cb.rsm_id, cb.ss_id, cb.parent_id, cb.brand_id, cb.subbrand_id, cb.flag_sku, cb.distributor_id ORDER BY cb.week::int) AS stm_qty_mtd_calc,

        -- 🕵️‍♂️ LOGIKA SAKTI LAST MONTH (LM): Mundur 4 baris minggu secara global melintasi batas tahun tanpa terikat sekat partisi year!
        LAG(SUM(cb.target_value) OVER (PARTITION BY cb.year, cb.period, cb.channel, cb.parent_id, cb.distributor_id, cb.brand_id, cb.subbrand_id, cb.flag_sku ORDER BY cb.week::int), 4) 
            OVER (PARTITION BY cb.channel, cb.sbu_id, cb.grsm_id, cb.rsm_id, cb.ss_id, cb.parent_id, cb.brand_id, cb.subbrand_id, cb.flag_sku, cb.distributor_id ORDER BY cb.year::int, cb.week::int) AS target_val_lm_calc,
        LAG(SUM(CASE WHEN cb.year::int = cb.cur_year AND cb.week::int <= cb.cur_week THEN cb.stm_value WHEN cb.year::int < cb.cur_year THEN cb.stm_value ELSE 0 END) OVER (PARTITION BY cb.year, cb.period, cb.channel, cb.parent_id, cb.distributor_id, cb.brand_id, cb.subbrand_id, cb.flag_sku ORDER BY cb.week::int), 4) 
            OVER (PARTITION BY cb.channel, cb.sbu_id, cb.grsm_id, cb.rsm_id, cb.ss_id, cb.parent_id, cb.brand_id, cb.subbrand_id, cb.flag_sku, bd.distributor_id ORDER BY cb.year::int, cb.week::int) AS stm_val_lm_calc,

        LAG(SUM(cb.target_qty) OVER (PARTITION BY cb.year, cb.period, cb.channel, cb.parent_id, cb.distributor_id, cb.brand_id, cb.subbrand_id, cb.flag_sku ORDER BY cb.week::int), 4) 
            OVER (PARTITION BY cb.channel, cb.sbu_id, cb.grsm_id, cb.rsm_id, cb.ss_id, cb.parent_id, cb.brand_id, cb.subbrand_id, cb.flag_sku, cb.distributor_id ORDER BY cb.year::int, cb.week::int) AS target_qty_lm_calc,
        LAG(SUM(CASE WHEN cb.year::int = cb.cur_year AND cb.week::int <= cb.cur_week THEN cb.stm_qty WHEN cb.year::int < cb.cur_year THEN cb.stm_qty ELSE 0 END) OVER (PARTITION BY cb.year, cb.period, cb.channel, cb.parent_id, cb.distributor_id, cb.brand_id, cb.subbrand_id, cb.flag_sku ORDER BY cb.week::int), 4) 
            OVER (PARTITION BY cb.channel, cb.sbu_id, cb.grsm_id, cb.rsm_id, cb.ss_id, cb.parent_id, cb.brand_id, cb.subbrand_id, cb.flag_sku, cb.distributor_id ORDER BY cb.year::int, cb.week::int) AS stm_qty_lm_calc
    FROM clean_base cb
),

unpivoted AS (
    -- 🔵 UNPIVOT QTY
    SELECT 
        channel, year, period, periodname, week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        
        'QTY' AS pilihan_satuan,
        
        -- 📦 DATA ORIGINAL MINGGUAN UTUH (Kunci 0 untuk STM masa depan)
        target_qty AS target_original,
        CASE WHEN year = cur_year AND week <= cur_week THEN stm_qty WHEN year < cur_year THEN stm_qty ELSE 0 END AS stm_original,
        CASE WHEN year = cur_year AND week <= cur_week THEN salfo_qty WHEN year < cur_year THEN salfo_qty ELSE 0 END AS salfo_original,
        
        -- 🔮 ESTIMASI PENGGANTI (Masa depan murni diisi oleh Salfo asli untuk pengisi STM)
        CASE WHEN year = cur_year AND week > cur_week THEN salfo_qty ELSE 0 END AS est_forward_original,
        
        -- ⚙️ DATA AGREGASI KALKULASI DASHBOARD
        target_qty_ytd_calc AS target_ytd, 
        stm_qty_ytd_calc AS stm_ytd, 
        target_qty_mtd_calc AS target_mtd, 
        stm_qty_mtd_calc AS stm_mtd,
        
        -- Pagar Pengaman Masa Depan
        CASE WHEN week <= cur_week THEN COALESCE(target_qty_lm_calc, 0) ELSE 0 END AS target_lm,
        CASE WHEN week <= cur_week THEN COALESCE(stm_qty_lm_calc, 0) ELSE 0 END AS stm_lm,
        CASE WHEN week <= cur_week THEN avg_5w_qty ELSE 0 END AS avg_5w_value,
        CASE WHEN week <= cur_week THEN avg_13w_qty ELSE 0 END AS avg_13w_value,
        
        -- 🛡️ INTEGRASI KOLOM STOCK & INVENTORY (Diteruskan utuh ke Gold)
        stock_qty, stock_value, stock_ibn, stock_ibn_value, fdos_update, fdos_value, sta_qty, sta_value,
        
        period AS min_urutan_period, week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM calculated_ytd_mtd

    UNION ALL

    -- 🟢 UNPIVOT VALUE
    SELECT 
        channel, year, period, periodname, week,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name, loaded_at,
        
        'VALUE' AS pilihan_satuan,
        
        -- 📦 DATA ORIGINAL MINGGUAN UTUH (Kunci 0 untuk STM masa depan)
        target_value AS target_original,
        CASE WHEN year = cur_year AND week <= cur_week THEN stm_value WHEN year < cur_year THEN stm_value ELSE 0 END AS stm_original,
        CASE WHEN year = cur_year AND week <= cur_week THEN salfo_value WHEN year < cur_year THEN salfo_value ELSE 0 END AS salfo_original,
        
        -- 🔮 ESTIMASI PENGGANTI (Masa depan murni diisi oleh Salfo asli untuk pengisi STM)
        CASE WHEN year = cur_year AND week > cur_week THEN salfo_value ELSE 0 END AS est_forward_original,
        
        -- ⚙️ DATA AGREGASI KALKULASI DASHBOARD
        target_val_ytd_calc AS target_ytd, 
        stm_val_ytd_calc AS stm_ytd, 
        target_val_mtd_calc AS target_mtd, 
        stm_val_mtd_calc AS stm_mtd,
        
        -- Pagar Pengaman Masa Depan
        CASE WHEN week <= cur_week THEN COALESCE(target_val_lm_calc, 0) ELSE 0 END AS target_lm,
        CASE WHEN week <= cur_week THEN COALESCE(stm_val_lm_calc, 0) ELSE 0 END AS stm_lm,
        CASE WHEN week <= cur_week THEN avg_5w_value ELSE 0 END AS avg_5w_value,
        CASE WHEN week <= cur_week THEN avg_13w_value ELSE 0 END AS avg_13w_value,
        
        -- 🛡️ INTEGRASI KOLOM STOCK & INVENTORY (Diteruskan utuh ke Gold)
        stock_qty, stock_value, stock_ibn, stock_ibn_value, fdos_update, fdos_value, sta_qty, sta_value,
        
        period AS min_urutan_period, week AS urutan_filter_week,
        CASE WHEN year = cur_year AND week = cur_week THEN 1 ELSE 0 END AS is_current_week
    FROM calculated_ytd_mtd
)
SELECT * FROM unpivoted