{{ config(
    materialized='table',
    alias='gold_performance_fdos',
    indexes=[
      {'columns': ['year', 'week', 'pilihan_satuan', 'ss_id']}
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

prep_data AS (
    SELECT 
        parent.*,
        c.cur_year AS op_current_year,
        c.cur_period AS op_current_period,
        c.cur_week AS op_current_week,
        CASE WHEN parent.week::numeric <= c.cur_week THEN 1 ELSE 0 END AS is_ytd
    FROM spx.silver_sales_performance_parent parent
    CROSS JOIN current_operational c
),

unpivoted_metrics AS (
    -- Blok QTY
    SELECT 
        year, period, week, channel, flag_sku, flag, 
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name, distributor_id, distributor_name,
        op_current_year, op_current_period, op_current_week, is_ytd,
        CURRENT_TIMESTAMP AS loaded_at,
        
        'QTY' AS pilihan_satuan,
        sta_qty AS sta_value_final,
        fdos_update AS fdos_value_final,
        stock_qty AS stock_subdist_final,
        avg_5w_qty AS avg_stm_5w_final
    FROM prep_data

    UNION ALL

    -- Blok VALUE
    SELECT 
        year, period, week, channel, flag_sku, flag, 
        sbu_id, sbu_name, brand_id, brand_name, subbrand_id, subbrand_name, parent_id, parent_name,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name, distributor_id, distributor_name,
        op_current_year, op_current_period, op_current_week, is_ytd,
        CURRENT_TIMESTAMP AS loaded_at,
        
        'VALUE' AS pilihan_satuan,
        sta_value AS sta_value_final,
        fdos_value AS fdos_value_final,
        stock_value AS stock_subdist_final,
        avg_5w_value AS avg_stm_5w_final
    FROM prep_data
)

SELECT * FROM unpivoted_metrics


-- WITH current_operational AS (
--     SELECT 
--         year::text AS cur_year,
--         period::text AS cur_period,
--         week::numeric AS cur_week
--     FROM spx.m_cycle3 
--     WHERE cdate::date = CURRENT_DATE
--     LIMIT 1
-- ),

-- -- Tarik data mentah langsung cross join dengan m_cycle3 untuk hitung is_ytd
-- prep_data AS (
--     SELECT 
--         fdos.*,
--         c.cur_year AS op_current_year,
--         c.cur_period AS op_current_period,
--         c.cur_week AS op_current_week,
--         CASE WHEN fdos.week::numeric <= c.cur_week THEN 1 ELSE 0 END AS is_ytd
--     FROM spx.silver_performance_fdos fdos
--     CROSS JOIN current_operational c
-- ),

-- -- Proses Unpivot Vertikal langsung dari prep_data
-- unpivoted_metrics AS (
--     -- Blok QTY
--     SELECT 
--         channel, year, period, week, flag, distributor_id, parent_id,
--         nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
--         op_current_year, op_current_period, op_current_week, is_ytd,
--         CURRENT_TIMESTAMP AS loaded_at,
        
--         'QTY' AS pilihan_satuan,
--         sta_qty AS sta_value_final,
--         fdos_update AS fdos_value_final
--     FROM prep_data

--     UNION ALL

--     -- Blok VALUE
--     SELECT 
--         channel, year, period, week, flag, distributor_id, parent_id,
--         nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name,
--         op_current_year, op_current_period, op_current_week, is_ytd,
--         CURRENT_TIMESTAMP AS loaded_at,
        
--         'VALUE' AS pilihan_satuan,
--         sta_value AS sta_value_final,
--         fdos_value AS fdos_value_final
--     FROM prep_data
-- )

-- SELECT * FROM unpivoted_metrics