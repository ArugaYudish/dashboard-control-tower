{{ config(
    materialized='table',
    alias='gold_forecast_kpi_by_period',
    indexes=[
      {'columns': ['year', 'period']},
      {'columns': ['parent_id']},
      {'columns': ['grsm_id']},
      {'columns': ['channel']}
    ]
) }}

WITH period_seq AS (
    -- Urutan periode kalender yang valid, dari master m_cycle3.
    -- row_number memberi "nomor urut global" sehingga previous = seq - 1,
    -- kebal terhadap pergantian tahun dan jumlah periode non-standar.
    SELECT
        year::int   AS year,
        period::int AS period,
        ROW_NUMBER() OVER (ORDER BY year::int, period::int) AS seq
    FROM (
        SELECT DISTINCT year, period
        FROM spx.m_cycle3
    ) d
),

agg AS (
    -- Agregasi actual & forecast per periode per dimensi (Interpretasi A).
    SELECT
        year::int   AS year,
        period::int AS period,
        channel,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name,
        ss_id, ss_name, sbu_id, sbu_name, brand_id, brand_name,
        subbrand_id, subbrand_name, parent_id, parent_name,
        SUM(salfo_value_final::numeric) AS total_forecast,
        SUM(stm_value_final::numeric)   AS total_actual
    FROM {{ ref('gold_sales_target_performance') }}
    WHERE pilihan_satuan = 'QTY'
    GROUP BY
        year, period, channel,
        nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name,
        ss_id, ss_name, sbu_id, sbu_name, brand_id, brand_name,
        subbrand_id, subbrand_name, parent_id, parent_name
),

-- Petakan tiap baris agg ke nomor urut periodenya, lalu ke nomor urut periode sebelumnya
agg_seq AS (
    SELECT a.*, ps.seq, ps.seq - 1 AS prev_seq
    FROM agg a
    JOIN period_seq ps ON a.year = ps.year AND a.period = ps.period
)

SELECT
    cur.year,
    cur.period,
    cur.channel,
    cur.nsm_id, cur.nsm_name, cur.grsm_id, cur.grsm_name, cur.rsm_id, cur.rsm_name,
    cur.ss_id, cur.ss_name, cur.sbu_id, cur.sbu_name, cur.brand_id, cur.brand_name,
    cur.subbrand_id, cur.subbrand_name, cur.parent_id, cur.parent_name,
    cur.total_forecast,
    cur.total_actual,
    -- Nilai periode SEBELUMNYA (kalender), untuk kombinasi dimensi yang sama.
    -- NULL jika bulan lalu memang tidak ada aktivitas untuk entity ini
    -- (benar secara semantik — bukan "loncat" ke bulan yang ada seperti LAG polos).
    prev.total_forecast AS total_forecast_prev,
    prev.total_actual   AS total_actual_prev
FROM agg_seq cur
LEFT JOIN agg_seq prev
    ON  cur.prev_seq      = prev.seq
    AND cur.channel       IS NOT DISTINCT FROM prev.channel
    AND cur.parent_id     IS NOT DISTINCT FROM prev.parent_id
    AND cur.grsm_id       IS NOT DISTINCT FROM prev.grsm_id
    AND cur.rsm_id        IS NOT DISTINCT FROM prev.rsm_id
    AND cur.ss_id         IS NOT DISTINCT FROM prev.ss_id