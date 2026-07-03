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

-- 1. DRIVER MASTER TARGET UTUH (Dinamis Mengikuti Semua Tahun yang Ada di Database)
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

-- 2. AMBIL REALISASI TRANSAKSI DAN FORECAST APA ADANYA
actual_sales AS (
    SELECT 
        year, period::numeric as period, week, pcode, channel, distributor_id,
        COALESCE(stm_qty, 0) AS stm_qty,
        COALESCE(stm_value, 0) AS stm_value,
        COALESCE(salfo_qty, 0) AS salfo_qty,
        COALESCE(salfo_value, 0) AS salfo_value
    FROM spx.silver_sales_performance
),

-- 3. GABUNGKAN SECARA HORIZONTAL STANDAR
matrix_base AS (
    SELECT 
        t.channel, t.year, t.period::text AS period, t.periodname, t.week,
        t.nsm_id, t.nsm_name, t.grsm_id, t.grsm_name, t.rsm_id, t.rsm_name, ss_id, ss_name,
        t.sbu_id, t.sbu_name, t.brand_id, t.brand_name, t.subbrand_id, t.subbrand_name, t.parent_id, t.parent_name,
        t.pcode, t.pcodename, t.flag_sku, t.distributor_id, t.distributor_name,
        t.op_current_year, t.op_current_period, t.op_current_week, t.is_ytd_calc,
        
        COALESCE(t.target_qty, 0) AS target_qty,
        COALESCE(t.target_value, 0) AS target_value,
        COALESCE(a.stm_qty, 0) AS stm_qty,
        COALESCE(a.stm_value, 0) AS stm_value,
        COALESCE(a.salfo_qty, 0) AS salfo_qty,
        COALESCE(a.salfo_value, 0) AS salfo_value
    FROM target_driver t
    LEFT JOIN actual_sales a 
        ON t.year = a.year AND t.week = a.week AND t.period = a.period
       AND t.pcode = a.pcode AND t.channel = a.channel AND t.distributor_id = a.distributor_id
)

-- 4. UNPIVOT STANDAR (QTY & VALUE)
SELECT 
    *, 'QTY' AS pilihan_satuan,
    target_qty AS target_value_final, 
    stm_qty AS stm_value_final, 
    salfo_qty AS salfo_value_final
FROM matrix_base

UNION ALL

SELECT 
    *, 'VALUE' AS pilihan_satuan,
    target_value AS target_value_final, 
    stm_value AS stm_value_final, 
    salfo_value AS salfo_value_final
FROM matrix_base