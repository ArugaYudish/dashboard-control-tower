{{ config(
    materialized='table',
    alias='gold_dashboard_sales_lm',
    indexes=[
      {'columns': ['match_year', 'match_period', 'pilihan_satuan', 'channel', 'distributor_id']}
    ]
) }}

WITH current_operational AS (
    SELECT 
        year::int AS cur_year,
        period::int AS cur_period,
        week::int AS cur_week
    FROM spx.m_cycle3 
    WHERE cdate::date = CURRENT_DATE
    LIMIT 1
),

monthly_summary AS (
    -- Ringkas seluruh isi data Silver menjadi level Bulanan (Murni tanpa kolom week!)
    SELECT 
        year::int AS agg_year,
        period::int AS agg_period,
        channel, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        flag_sku, distributor_id, distributor_name,
        SUM(target_qty) AS target_qty_lm,
        SUM(CASE WHEN year = 2026 AND week <= (SELECT cur_week FROM current_operational) THEN stm_qty WHEN year < 2026 THEN stm_qty ELSE 0 END) AS stm_qty_lm,
        SUM(target_value) AS target_val_lm,
        SUM(CASE WHEN year = 2026 AND week <= (SELECT cur_week FROM current_operational) THEN stm_value WHEN year < 2026 THEN stm_value ELSE 0 END) AS stm_val_lm
    FROM spx.silver_sales_performance_parent
    WHERE week IS NOT NULL
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21
),

shifted_time AS (
    -- 🚀 LOGIKA UTAMA: Majukan periodenya (+1) agar pas user filter di Superset, datanya otomatis match mundur ke bulan lalu!
    SELECT 
        *,
        -- Jika bulan lalu periode 12, maka dipasangkan ke Periode 1 Tahun Depan
        CASE WHEN agg_period = 12 THEN agg_year + 1 ELSE agg_year END AS match_year,
        CASE WHEN agg_period = 12 THEN 1 ELSE agg_period + 1 END AS match_period
    FROM monthly_summary
)

-- Proses UNPIVOT untuk menyamakan pilihan_satuan QTY/VALUE
SELECT 
    channel, match_year AS year, match_period AS period, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
    sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
    flag_sku, distributor_id, distributor_name,
    'QTY' AS pilihan_satuan,
    target_qty_lm AS target_lm,
    stm_qty_lm AS stm_lm
FROM shifted_time

UNION ALL

SELECT 
    channel, match_year AS year, match_period AS period, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
    sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
    flag_sku, distributor_id, distributor_name,
    'VALUE' AS pilihan_satuan,
    target_val_lm AS target_lm,
    stm_val_lm AS stm_lm
FROM shifted_time