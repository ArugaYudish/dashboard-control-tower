{{ config(
    materialized='table',
    alias='gold_forecast_kpi_detail',
    indexes=[
      {'columns': ['parent_id']},
      {'columns': ['channel']}
    ]
) }}

WITH base AS (
    SELECT *
    FROM {{ ref('gold_sales_target_performance') }}
    WHERE pilihan_satuan = 'QTY'
),

last_month_ref AS (
    SELECT DISTINCT
        op_current_year,
        op_current_period,
        CASE WHEN op_current_period::int = 1 
             THEN (op_current_year::int - 1)::text 
             ELSE op_current_year 
        END AS lm_year,
        CASE WHEN op_current_period::int = 1 
             THEN '12' 
             ELSE (op_current_period::int - 1)::text 
        END AS lm_period
    FROM base
),

mtd_agg AS (
    SELECT
        channel, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name,
        ss_id, ss_name, sbu_id, sbu_name, brand_id, brand_name,
        subbrand_id, subbrand_name, parent_id, parent_name,
        SUM(salfo_value_final::numeric) AS total_forecast_mtd,
        SUM(stm_value_final::numeric) AS total_actual_mtd
    FROM base
    WHERE year::text = op_current_year
      AND period::text = op_current_period
      AND is_ytd = 1
    GROUP BY channel, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name,
        ss_id, ss_name, sbu_id, sbu_name, brand_id, brand_name,
        subbrand_id, subbrand_name, parent_id, parent_name
),

lm_agg AS (
    SELECT
        b.channel, b.nsm_id, b.nsm_name, b.grsm_id, b.grsm_name, b.rsm_id, b.rsm_name,
        b.ss_id, b.ss_name, b.sbu_id, b.sbu_name, b.brand_id, b.brand_name,
        b.subbrand_id, b.subbrand_name, b.parent_id, b.parent_name,
        SUM(b.salfo_value_final::numeric) AS total_forecast_lm,
        SUM(b.stm_value_final::numeric) AS total_actual_lm
    FROM base b
    JOIN last_month_ref lm
      ON b.op_current_year = lm.op_current_year
     AND b.op_current_period = lm.op_current_period
    WHERE b.year::text = lm.lm_year
      AND b.period::text = lm.lm_period
    GROUP BY b.channel, b.nsm_id, b.nsm_name, b.grsm_id, b.grsm_name, b.rsm_id, b.rsm_name,
        b.ss_id, b.ss_name, b.sbu_id, b.sbu_name, b.brand_id, b.brand_name,
        b.subbrand_id, b.subbrand_name, b.parent_id, b.parent_name
)

SELECT
    COALESCE(m.channel, l.channel) AS channel,
    COALESCE(m.nsm_id, l.nsm_id) AS nsm_id,
    COALESCE(m.nsm_name, l.nsm_name) AS nsm_name,
    COALESCE(m.grsm_id, l.grsm_id) AS grsm_id,
    COALESCE(m.grsm_name, l.grsm_name) AS grsm_name,
    COALESCE(m.rsm_id, l.rsm_id) AS rsm_id,
    COALESCE(m.rsm_name, l.rsm_name) AS rsm_name,
    COALESCE(m.ss_id, l.ss_id) AS ss_id,
    COALESCE(m.ss_name, l.ss_name) AS ss_name,
    COALESCE(m.sbu_id, l.sbu_id) AS sbu_id,
    COALESCE(m.sbu_name, l.sbu_name) AS sbu_name,
    COALESCE(m.brand_id, l.brand_id) AS brand_id,
    COALESCE(m.brand_name, l.brand_name) AS brand_name,
    COALESCE(m.subbrand_id, l.subbrand_id) AS subbrand_id,
    COALESCE(m.subbrand_name, l.subbrand_name) AS subbrand_name,
    COALESCE(m.parent_id, l.parent_id) AS parent_id,
    COALESCE(m.parent_name, l.parent_name) AS parent_name,
    COALESCE(m.total_forecast_mtd, 0) AS total_forecast_mtd,
    COALESCE(m.total_actual_mtd, 0) AS total_actual_mtd,
    COALESCE(l.total_forecast_lm, 0) AS total_forecast_lm,
    COALESCE(l.total_actual_lm, 0) AS total_actual_lm
FROM mtd_agg m
FULL OUTER JOIN lm_agg l 
    ON m.parent_id = l.parent_id 
   AND m.channel = l.channel
   AND m.nsm_id = l.nsm_id
   AND m.rsm_id = l.rsm_id
   AND m.ss_id = l.ss_id