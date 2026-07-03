{{ config(
    materialized='table',
    alias='gold_sales_target_performance',
    indexes=[
      {'columns': ['year', 'week', 'pcode', 'pilihan_satuan']}
    ]
) }}

WITH current_operational AS (
    SELECT 
        year::text AS cur_year,
        period::text AS cur_period,
        week::numeric AS cur_week
    FROM spx.m_cycle3 
    WHERE cdate::date = CURRENT_DATE
    LIMIT 1
),

-- 1. Siapkan Data Tahun Ini (TY)
data_ty AS (
    SELECT 
        stp.*,
        c.cur_year AS op_current_year,
        c.cur_period AS op_current_period,
        c.cur_week AS op_current_week,
        CASE WHEN stp.week::numeric <= c.cur_week THEN 1 ELSE 0 END AS is_ytd_calc
    FROM spx.silver_target_performance stp
    CROSS JOIN current_operational c
),

-- 2. Siapkan Data Tahun Lalu (LY)
data_ly AS (
    SELECT 
        stp.*,
        c.cur_year AS op_current_year,
        c.cur_period AS op_current_period,
        c.cur_week AS op_current_week,
        CASE WHEN stp.week::numeric <= c.cur_week THEN 1 ELSE 0 END AS is_ytd_calc
    FROM spx.silver_target_performance stp
    CROSS JOIN current_operational c
),

-- 3. Satukan Menggunakan FULL OUTER JOIN & Amankan Kolom Dimensi
matrix_combined AS (
    SELECT 
        -- Kunci Wajib Dashboard: Jika data 2026 kosong, paksa year diisi (tahun 2025 + 1) alias 2026 agar filter global tahun 2026 Superset tetep menangkap baris ini
        COALESCE(t1.year, (t2.year + 1)) AS year,
        COALESCE(t1.period, t2.period) AS period,
        COALESCE(t1.periodname, t2.periodname) AS periodname,
        COALESCE(t1.week, t2.week) AS week,
        COALESCE(t1.flag, t2.flag) AS flag,
        COALESCE(t1.channel, t2.channel) AS channel,
        COALESCE(t1.pcode, t2.pcode) AS pcode,
        COALESCE(t1.pcodename, t2.pcodename) AS pcodename,
        COALESCE(t1.flag_sku, t2.flag_sku) AS flag_sku,
        COALESCE(t1.distributor_id, t2.distributor_id) AS distributor_id,
        COALESCE(t1.distributor_name, t2.distributor_name) AS distributor_name,
        
        -- Hierarki Management Sales Force Mayora
        COALESCE(t1.nsm_id, t2.nsm_id) AS nsm_id,
        COALESCE(t1.nsm_name, t2.nsm_name) AS nsm_name,
        COALESCE(t1.grsm_id, t2.grsm_id) AS grsm_id,
        COALESCE(t1.grsm_name, t2.grsm_name) AS grsm_name,
        COALESCE(t1.rsm_id, t2.rsm_id) AS rsm_id,
        COALESCE(t1.rsm_name, t2.rsm_name) AS rsm_name,
        COALESCE(t1.ss_id, t2.ss_id) AS ss_id,
        COALESCE(t1.ss_name, t2.ss_name) AS ss_name,
        
        -- Hierarki Product Management
        COALESCE(t1.sbu_id, t2.sbu_id) AS sbu_id,
        COALESCE(t1.sbu_name, t2.sbu_name) AS sbu_name,
        COALESCE(t1.brand_id, t2.brand_id) AS brand_id,
        COALESCE(t1.brand_name, t2.brand_name) AS brand_name,
        COALESCE(t1.subbrand_id, t2.subbrand_id) AS subbrand_id,
        COALESCE(t1.subbrand_name, t2.subbrand_name) AS subbrand_name,
        COALESCE(t1.parent_id, t2.parent_id) AS parent_id,
        COALESCE(t1.parent_name, t2.parent_name) AS parent_name,
        
        -- Dimensi Master Operasional Cycle
        COALESCE(t1.op_current_year, t2.op_current_year) AS op_current_year,
        COALESCE(t1.op_current_period, t2.op_current_period) AS op_current_period,
        COALESCE(t1.op_current_week, t2.op_current_week) AS op_current_week,
        COALESCE(t1.is_ytd_calc, t2.is_ytd_calc) AS is_ytd,

        -- Nilai Transaksi Tahun Ini (TY)
        COALESCE(t1.target_qty, 0) AS target_qty,
        COALESCE(t1.target_value, 0) AS target_value,
        COALESCE(t1.stm_qty, 0) AS stm_qty,
        COALESCE(t1.stm_value, 0) AS stm_value,
        COALESCE(t1.salfo_qty, 0) AS salfo_qty,
        COALESCE(t1.salfo_value, 0) AS salfo_value,

        -- Nilai Transaksi Tahun Lalu (LY) Pembanding
        COALESCE(t2.stm_qty, 0) AS stm_qty_ly,
        COALESCE(t2.stm_value, 0) AS stm_value_ly
    FROM data_ty t1
    FULL OUTER JOIN data_ly t2 
        ON (t1.year - 1) = t2.year 
       AND t1.week = t2.week 
       AND t1.pcode = t2.pcode
       AND t1.channel = t2.channel
       AND t1.distributor_id = t2.distributor_id
)

-- 4. PROSES UNPIVOT VERTIKAL
-- Blok QTY
SELECT 
    year, period, periodname, week, flag, channel, pcode, pcodename, flag_sku, distributor_id, distributor_name,
    nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
    sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
    op_current_year, op_current_period, op_current_week, is_ytd,
    'QTY' AS pilihan_satuan, 
    target_qty AS target_value_final, 
    stm_qty AS stm_value_final,
    salfo_qty AS salfo_value_final,
    stm_qty_ly AS stm_value_ly_final
FROM matrix_combined

UNION ALL

-- Blok VALUE
SELECT 
    year, period, periodname, week, flag, channel, pcode, pcodename, flag_sku, distributor_id, distributor_name,
    nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
    sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
    op_current_year, op_current_period, op_current_week, is_ytd,
    'VALUE' AS pilihan_satuan, 
    target_value AS target_value_final, 
    stm_value AS stm_value_final,
    salfo_value AS salfo_value_final,
    stm_value_ly AS stm_value_ly_final
FROM matrix_combined