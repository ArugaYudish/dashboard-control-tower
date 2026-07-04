{{ config(
    materialized='table',
    alias='gold_sales_projection_full_year',
    indexes=[
      {'columns': ['year', 'period', 'week', 'pilihan_satuan']}
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

-- 1. KUNCI MUTLAK: Hitung total target murni 1 tahun penuh di level paling atas (Hanya per TAHUN)
target_total_tahun AS (
    SELECT 
        year,
        SUM(target_qty) AS target_qty_pure_year,
        SUM(target_value) AS target_val_pure_year
    FROM spx.silver_target_performance
    GROUP BY year
),

target_driver AS (
    SELECT 
        t.*,
        c.cur_year AS op_current_year,
        c.cur_period AS op_current_period,
        c.cur_week AS op_current_week,
        CASE WHEN t.week::numeric <= c.cur_week THEN 1 ELSE 0 END AS is_ytd_calc
    FROM spx.silver_target_performance t
    CROSS JOIN current_operational c
),

actual_sales AS (
    SELECT 
        year, period::numeric as period, week, pcode, channel, distributor_id,
        COALESCE(stm_qty, 0) AS stm_qty,
        COALESCE(stm_value, 0) AS stm_value,
        COALESCE(salfo_qty, 0) AS salfo_qty,
        COALESCE(salfo_value, 0) AS salfo_value
    FROM spx.silver_sales_performance
),

matrix_base AS (
    SELECT 
        t.channel, t.year, t.period::text AS period, t.periodname, t.week,
        t.nsm_id, t.nsm_name, t.grsm_id, t.grsm_name, t.rsm_id, t.rsm_name, t.ss_id, t.ss_name,
        t.sbu_id, t.sbu_name, t.brand_id, t.brand_name, t.subbrand_id, t.subbrand_name, t.parent_id, t.parent_name,
        t.pcode, t.pcodename, t.flag_sku, t.distributor_id, t.distributor_name,
        t.op_current_year, t.op_current_period, t.op_current_week, t.is_ytd_calc,
        
        COALESCE(t.target_qty, 0) AS target_qty,
        COALESCE(t.target_value, 0) AS target_value,
        COALESCE(a.stm_qty, 0) AS stm_qty,
        COALESCE(a.stm_value, 0) AS stm_value,
        COALESCE(a.salfo_qty, 0) AS salfo_qty,
        COALESCE(a.salfo_value, 0) AS salfo_value,
        
        -- Masukkan angka total tahunan murni nasional ke dalam baris tanpa group by atribut lain
        COALESCE(n.target_qty_pure_year, 0) AS target_year_helper_qty,
        COALESCE(n.target_val_pure_year, 0) AS target_year_helper_val
    FROM target_driver t
    LEFT JOIN target_total_tahun n ON t.year = n.year -- JOIN murni level tahun, kebal dari filter kualitatif apa pun
    LEFT JOIN actual_sales a 
        ON t.year = a.year 
       AND t.week = a.week 
       AND t.period::text = a.period::text
       AND t.pcode = a.pcode 
       AND t.channel = a.channel 
       AND t.distributor_id = a.distributor_id
),

matrix_with_lm AS (
    SELECT 
        curr.*,
        COALESCE(prev.target_qty, 0) AS target_qty_lm,
        COALESCE(prev.target_value, 0) AS target_value_lm,
        COALESCE(prev.stm_qty, 0) AS stm_qty_lm,
        COALESCE(prev.stm_value, 0) AS stm_value_lm
    FROM matrix_base curr
    LEFT JOIN matrix_base prev
        ON prev.channel = curr.channel
       AND prev.distributor_id = curr.distributor_id
       AND prev.pcode = curr.pcode
       AND prev.year = CASE WHEN curr.period = '1' THEN (curr.year - 1) ELSE curr.year END
       AND prev.period = CASE WHEN curr.period = '1' THEN '12' ELSE (curr.period::numeric - 1)::text END
       AND (prev.week::numeric % 4) = (curr.week::numeric % 4)
)

SELECT 
    *, 'QTY' AS pilihan_satuan,
    target_qty AS target_value_final, 
    stm_qty AS stm_value_final, 
    salfo_qty AS salfo_value_final,
    target_qty_lm AS target_lm_final,
    stm_qty_lm AS stm_lm_final,
    target_year_helper_qty AS target_year_helper
FROM matrix_with_lm

UNION ALL

SELECT 
    *, 'VALUE' AS pilihan_satuan,
    target_value AS target_value_final, 
    stm_value AS stm_value_final, 
    salfo_value AS salfo_value_final,
    target_value_lm AS target_lm_final,
    stm_value_lm AS stm_lm_final,
    target_year_helper_val AS target_year_helper
FROM matrix_with_lm