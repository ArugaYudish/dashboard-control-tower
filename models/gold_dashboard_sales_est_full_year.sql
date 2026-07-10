{{ config(
    materialized='table',
    alias='gold_dashboard_sales_est_full_year',
    indexes=[
      {'columns': ['year', 'pilihan_satuan', 'channel', 'distributor_id', 'parent_id']}
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

yearly_calculation AS (
    -- 🛑 2. AGREGASI TOTAL FULL YEAR LANGSUNG DARI SILVER (ANTI-BOCOR FILTER WAKTU)
    SELECT 
        s.year::int AS agg_year,
        s.channel, s.nsm_id, s.nsm_name, s.grsm_id, s.grsm_name, s.rsm_id, s.rsm_name, s.ss_id, s.ss_name,
        s.sbu_id, s.sbu_name, s.brand_id, s.brand_name, s.subbrand_id, s.subbrand_name, s.parent_id, s.parent_name,
        s.flag_sku, s.distributor_id, s.distributor_name,
        
        -- Kalkulasi QTY Setahun Penuh
        SUM(s.target_qty) AS target_qty_full_year,
        SUM(CASE 
            WHEN s.year::int = c.cur_year AND s.week::int <= c.cur_week THEN s.stm_qty 
            WHEN s.year::int < c.cur_year THEN s.stm_qty 
            ELSE 0 
        END) +
        SUM(CASE 
            WHEN s.year::int = c.cur_year AND s.week::int > c.cur_week THEN s.salfo_qty 
            ELSE 0 
        END) AS est_stm_qty_full_year,

        -- Kalkulasi VALUE Setahun Penuh
        SUM(s.target_value) AS target_val_full_year,
        SUM(CASE 
            WHEN s.year::int = c.cur_year AND s.week::int <= c.cur_week THEN s.stm_value 
            WHEN s.year::int < c.cur_year THEN s.stm_value 
            ELSE 0 
        END) +
        SUM(CASE 
            WHEN s.year::int = c.cur_year AND s.week::int > c.cur_week THEN s.salfo_value 
            ELSE 0 
        END) AS est_stm_val_full_year

    FROM spx.silver_sales_performance_parent s
    CROSS JOIN current_operational c
    WHERE s.week IS NOT NULL AND s.year::int IN (c.cur_year, c.cur_year - 1)
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21
)

-- 🔵 UNPIVOT QTY
SELECT 
    channel, agg_year AS year, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
    sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
    flag_sku, distributor_id, distributor_name,
    'QTY' AS pilihan_satuan,
    target_qty_full_year AS target_full_year,
    est_stm_qty_full_year AS est_full_year
FROM yearly_calculation

UNION ALL

-- 🟢 UNPIVOT VALUE
SELECT 
    channel, agg_year AS year, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
    sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
    flag_sku, distributor_id, distributor_name,
    'VALUE' AS pilihan_satuan,
    target_val_full_year AS target_full_year,
    est_stm_val_full_year AS est_full_year
FROM yearly_calculation