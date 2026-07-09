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

-- 2. Gabungkan data Silver dengan helper target tahunan
base_data AS (
    SELECT 
        s.*,
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
-- 🔀 UNPIVOT MURNI 1-TO-1 DARI SILVER (ANTI MELEDAK / RUN 5 DETIK)
-- =========================================================================

-- 🔵 1. BLOK DATA QTY
SELECT 
    channel, year, period, periodname, week::numeric AS week,
    nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
    sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
    flag_sku, distributor_id, distributor_name, NOW() AS loaded_at,
    op_current_year, op_current_period, op_current_week, is_ytd_calc, op_last_period,
    
    'QTY' AS pilihan_satuan,
    target_qty AS target_weekly,
    stm_qty AS stm_weekly,
    
    -- Kolom pendukung LY (Last Year) untuk mode Growth YTD di plugin
    COALESCE(stm_qty_ly, 0) AS stm_weekly_ly, 
    
    -- Kolom pendukung Salfo dan Target Setahun untuk mode Est. Achievement di plugin
    COALESCE(salfo_qty, 0) AS salfo_weekly,
    target_qty_fy AS target_full_year_statis
FROM base_data

UNION ALL

-- 🟢 2. BLOK DATA VALUE
SELECT 
    channel, year, period, periodname, week::numeric AS week,
    nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
    sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
    flag_sku, distributor_id, distributor_name, NOW() AS loaded_at,
    op_current_year, op_current_period, op_current_week, is_ytd_calc, op_last_period,
    
    'VALUE' AS pilihan_satuan,
    target_value AS target_weekly,
    stm_value AS stm_weekly,
    
    -- Kolom pendukung LY (Last Year) untuk mode Growth YTD di plugin
    COALESCE(stm_value_ly, 0) AS stm_weekly_ly,
    
    -- Kolom pendukung Salfo dan Target Setahun untuk mode Est. Achievement di plugin
    COALESCE(salfo_value, 0) AS salfo_weekly,
    target_val_fy AS target_full_year_statis
FROM base_data