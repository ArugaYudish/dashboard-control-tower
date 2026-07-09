{{ config(
    materialized='table',
    alias='gold_dashboard_sales_ssot',
    indexes=[
      {'columns': ['year', 'period', 'week', 'pilihan_satuan', 'channel', 'parent_id', 'distributor_id', 'rsm_id']}
    ]
) }}

WITH current_operational AS (
    SELECT 
        year::numeric AS cur_year,
        period::numeric AS cur_period,
        week::numeric AS cur_week
    FROM spx.m_cycle3 
    WHERE cdate::date = CURRENT_DATE
    LIMIT 1
),

-- 1. Hitung total target setahun penuh per entitas unik untuk helper Est. Achievement
full_year_target AS (
    SELECT 
        year, channel, sbu_id, parent_id, brand_id, subbrand_id, flag_sku, distributor_id, rsm_id, ss_id,
        SUM(target_qty::numeric(20,4)) AS target_qty_full_year,
        SUM(target_value::numeric(20,4)) AS target_val_full_year
    FROM spx.silver_sales_performance_parent
    GROUP BY year, channel, sbu_id, parent_id, brand_id, subbrand_id, flag_sku, distributor_id, rsm_id, ss_id
),

-- 2. Amankan penarikan data murni dari Silver beralias eksplisit
base_data AS (
    SELECT 
        s.channel, s.year, s.period, s.periodname, s.week,
        s.nsm_id, s.nsm_name, s.grsm_id, s.grsm_name, s.rsm_id, s.rsm_name, s.ss_id, s.ss_name,
        s.sbu_id, s.sbu_name, s.brand_id, s.brand_name, s.subbrand_id, s.subbrand_name, s.parent_id, s.parent_name,
        s.flag_sku, s.distributor_id, s.distributor_name,
        s.target_qty, s.stm_qty, s.salfo_qty,
        s.target_value, s.stm_value, s.salfo_value,
        COALESCE(t.target_qty_full_year, 0) AS target_qty_fy,
        COALESCE(t.target_val_full_year, 0) AS target_val_fy,
        c.cur_year AS op_current_year,
        c.cur_period AS op_current_period,
        c.cur_week AS op_current_week,
        CASE WHEN s.week::numeric <= c.cur_week THEN 1 ELSE 0 END AS is_ytd_calc,
        CASE WHEN c.cur_period = 1 THEN 12 ELSE (c.cur_period - 1) END AS op_last_period
    FROM spx.silver_sales_performance_parent s
    LEFT JOIN full_year_target t
        ON s.year = t.year AND s.channel = t.channel AND s.sbu_id = t.sbu_id AND s.parent_id = t.parent_id 
       AND s.brand_id = t.brand_id AND s.subbrand_id = t.subbrand_id AND s.flag_sku = t.flag_sku 
       AND s.distributor_id = t.distributor_id AND s.ss_id = t.ss_id AND s.rsm_id = t.rsm_id
    CROSS JOIN current_operational c
    WHERE s.week IS NOT NULL
)

-- =========================================================================
-- 🔀 UNPIVOT MURNI 1-TO-1 (ANTI AMBIGUITAS SELEKSI KOLOM)
-- =========================================================================

-- 🔵 1. BLOK DATA QTY
SELECT 
    b.channel, b.year, b.period, b.periodname, b.week,
    b.nsm_id, b.nsm_name, b.grsm_id, b.grsm_name, b.rsm_id, b.rsm_name, b.ss_id, b.ss_name,
    b.sbu_id, b.sbu_name, b.brand_id, b.brand_name, b.subbrand_id, b.subbrand_name, b.parent_id, b.parent_name,
    b.flag_sku, b.distributor_id, b.distributor_name, NOW() AS loaded_at,
    b.op_current_year, b.op_current_period, b.op_current_week, b.is_ytd_calc, b.op_last_period,
    
    'QTY' AS pilihan_satuan,
    b.target_qty AS target_weekly,
    b.stm_qty AS stm_weekly,
    
    -- Kolom pendukung dummy LY karena absen di Silver skema
    0::numeric(20,4) AS stm_weekly_ly, 
    
    -- Kolom pendukung Salfo riil dan Target Setahun dari skema di atas
    b.salfo_qty AS salfo_weekly,
    b.target_qty_fy AS target_full_year_statis
FROM base_data b

UNION ALL

-- 🟢 2. BLOK DATA VALUE
SELECT 
    b.channel, b.year, b.period, b.periodname, b.week,
    b.nsm_id, b.nsm_name, b.grsm_id, b.grsm_name, b.rsm_id, b.rsm_name, b.ss_id, b.ss_name,
    b.sbu_id, b.sbu_name, b.brand_id, b.brand_name, b.subbrand_id, b.subbrand_name, b.parent_id, b.parent_name,
    b.flag_sku, b.distributor_id, b.distributor_name, NOW() AS loaded_at,
    b.op_current_year, b.op_current_period, b.op_current_week, b.is_ytd_calc, b.op_last_period,
    
    'VALUE' AS pilihan_satuan,
    b.target_value AS target_weekly,
    b.stm_value AS stm_weekly,
    
    -- Kolom pendukung dummy LY karena absen di Silver skema
    0::numeric(20,4) AS stm_weekly_ly,
    
    -- Kolom pendukung Salfo riil dan Target Setahun dari skema di atas
    b.salfo_value AS salfo_weekly,
    b.target_val_fy AS target_full_year_statis
FROM base_data b