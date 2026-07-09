{{ config(
    materialized='table',
    alias='gold_forecast_kpi_by_period',
    indexes=[
      {'columns': ['year', 'period']},
      {'columns': ['seq']},
      {'columns': ['parent_id']},
      {'columns': ['grsm_id']},
      {'columns': ['rsm_id']},
      {'columns': ['ss_id']},
      {'columns': ['channel']}
    ]
) }}

WITH agg AS (
    SELECT
        year::int AS year, period::int AS period,
        channel, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name,
        ss_id, ss_name, sbu_id, sbu_name, brand_id, brand_name,
        subbrand_id, subbrand_name, parent_id, parent_name,
        SUM(salfo_value_final::numeric) AS total_forecast,
        SUM(stm_value_final::numeric)   AS total_actual
    FROM {{ ref('gold_sales_target_performance') }}
    WHERE pilihan_satuan = 'QTY'
    GROUP BY
        year, period, channel, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name,
        ss_id, ss_name, sbu_id, sbu_name, brand_id, brand_name,
        subbrand_id, subbrand_name, parent_id, parent_name
),

agg_seq AS (
    SELECT a.*, ps.seq, ps.seq - 1 AS prev_seq
    FROM agg a
    JOIN {{ ref('dim_period_seq') }} ps ON a.year = ps.year AND a.period = ps.period
)

SELECT
    cur.year,
    cur.period,
    cur.seq,
    cur.channel,
    cur.nsm_id, cur.nsm_name, cur.grsm_id, cur.grsm_name, cur.rsm_id, cur.rsm_name,
    cur.ss_id, cur.ss_name, cur.sbu_id, cur.sbu_name, cur.brand_id, cur.brand_name,
    cur.subbrand_id, cur.subbrand_name, cur.parent_id, cur.parent_name,
    cur.total_forecast,
    cur.total_actual,
    prev.total_forecast AS total_forecast_prev,
    prev.total_actual   AS total_actual_prev
FROM agg_seq cur
LEFT JOIN agg_seq prev
    ON  cur.prev_seq       = prev.seq
    -- Fix 9-key: cocokkan seluruh dimensi (bukan cuma 5) supaya entity
    -- dengan multi-mapping (mis. subbrand_id ganda) tidak fan-out.
    -- Kalau belum siap terapkan, sementara boleh dipangkas ke 5 kolom
    -- (channel, parent_id, grsm_id, rsm_id, ss_id) seperti versi lama.
    AND cur.channel        IS NOT DISTINCT FROM prev.channel
    AND cur.nsm_id          IS NOT DISTINCT FROM prev.nsm_id
    AND cur.grsm_id         IS NOT DISTINCT FROM prev.grsm_id
    AND cur.rsm_id          IS NOT DISTINCT FROM prev.rsm_id
    AND cur.ss_id           IS NOT DISTINCT FROM prev.ss_id
    AND cur.sbu_id          IS NOT DISTINCT FROM prev.sbu_id
    AND cur.brand_id        IS NOT DISTINCT FROM prev.brand_id
    AND cur.subbrand_id     IS NOT DISTINCT FROM prev.subbrand_id
    AND cur.parent_id       IS NOT DISTINCT FROM prev.parent_id