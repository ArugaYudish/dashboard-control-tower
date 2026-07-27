{{ config(
    materialized='table',
    alias='gold_forecast_kpi_by_period',
    pre_hook=[
      "set local work_mem = '512MB'",
      "set local maintenance_work_mem = '1GB'"
    ],
    indexes=[
      {'columns': ['year', 'period']},
      {'columns': ['seq']},
      {'columns': ['periods_ago']},
      {'columns': ['parent_id']},
      {'columns': ['grsm_id']},
      {'columns': ['rsm_id']},
      {'columns': ['ss_id']},
      {'columns': ['channel']}
    ]
) }}

WITH agg AS (
    -- Salfo dibaca langsung dari silver_sales_performance_parent, sama persis
    -- dengan silver_sales_performance_chart (CTE `base` -> `cy_rows.salfo`).
    -- Sebelumnya lewat gold_sales_target_performance, yang menggeser angka salfo:
    --   1. tahun di-hardcode TY=2026 / LY=2025, jadi salfo 2025 hilang dan
    --      tabel ini otomatis kosong saat ganti tahun;
    --   2. FULL OUTER JOIN TY<->LY tidak memakai `period` sebagai kunci
    --      (chart memakainya), jadi minggu yang membelah dua periode di
    --      m_cycle3 menggandakan baris TY -> salfo ikut terlipat;
    --   3. baris LY-only ikut dicap year TY dengan salfo 0, menambah grup
    --      (period, hierarki) berisi nol yang tidak ada di chart.
    -- QTY tetap satu-satunya satuan, sama seperti filter pilihan_satuan lama.
    --
    -- GROUP BY hanya memakai kolom id. Kolom *_name sebelumnya ikut jadi kunci
    -- grouping: 9 kolom varchar ekstra pada hash key untuk 8,6 juta baris,
    -- padahal setiap name bergantung fungsional pada id-nya (diverifikasi:
    -- tidak ada satu pun id di silver yang memetakan ke >1 name, subbrand_name
    -- dicek terhadap pasangan brand_id+subbrand_id karena subbrand_id tidak
    -- unik global). MIN(name) karena itu memilih dari satu nilai saja ->
    -- baris hasil identik, tapi hash key menyusut jadi 10 kolom.
    SELECT
        year::int   AS year,
        period::int AS period,
        channel,
        nsm_id, grsm_id, rsm_id, ss_id,
        sbu_id, brand_id, subbrand_id, parent_id,
        MIN(nsm_name)      AS nsm_name,
        MIN(grsm_name)     AS grsm_name,
        MIN(rsm_name)      AS rsm_name,
        MIN(ss_name)       AS ss_name,
        MIN(sbu_name)      AS sbu_name,
        MIN(brand_name)    AS brand_name,
        MIN(subbrand_name) AS subbrand_name,
        MIN(parent_name)   AS parent_name,
        -- salfo_qty & stm_qty sudah numeric di silver, cast ::numeric lama
        -- adalah no-op. COALESCE dipindah ke luar SUM: SUM mengabaikan NULL,
        -- jadi grup yang seluruhnya NULL tetap menghasilkan 0 seperti semula,
        -- tanpa membayar COALESCE per baris.
        SUM(salfo_qty)             AS total_forecast,
        COALESCE(SUM(stm_qty), 0)  AS total_actual
    FROM {{ ref('silver_sales_performance_parent') }}
    GROUP BY
        year, period, channel,
        nsm_id, grsm_id, rsm_id, ss_id,
        sbu_id, brand_id, subbrand_id, parent_id
),

agg_seq AS (
    SELECT
        a.*,
        ps.seq
    FROM agg a
    JOIN {{ ref('dim_period_seq') }} ps
        ON a.year = ps.year AND a.period = ps.period
),

-- Nilai periode sebelumnya diambil lewat LAG, bukan self-join.
-- Self-join lama memakai `IS NOT DISTINCT FROM` pada 9 kolom dimensi; predikat
-- itu tidak bisa dipakai Postgres sebagai kunci hash/merge, jadi satu-satunya
-- kunci join yang efektif adalah `cur.seq - 1 = prev.seq`. Dengan hanya ~12-19
-- nilai seq berbeda, setiap seq mempertemukan ratusan ribu baris cur dengan
-- ratusan ribu baris prev, lalu 9 predikat dievaluasi sebagai filter di atas
-- hasil kali kartesian itu -- run terakhir: 43 menit lalu backend mati.
--
-- PARTITION BY memperlakukan NULL sebagai sama persis seperti IS NOT DISTINCT
-- FROM, dan agg dijamin hanya punya satu baris per (dimensi, seq) -- seq 1:1
-- dengan (year, period) di dim_period_seq -- sehingga LAG menghasilkan
-- pasangan yang sama dengan LEFT JOIN lama. Biayanya satu sort/hash, sekali.
lagged AS (
    SELECT
        s.*,
        LAG(s.seq)            OVER w AS prev_seq,
        LAG(s.total_forecast) OVER w AS prev_forecast,
        LAG(s.total_actual)   OVER w AS prev_actual
    FROM agg_seq s
    WINDOW w AS (
        PARTITION BY s.channel, s.nsm_id, s.grsm_id, s.rsm_id, s.ss_id,
                     s.sbu_id, s.brand_id, s.subbrand_id, s.parent_id
        ORDER BY s.seq
    )
)

SELECT
    year,
    period,
    seq,
    -- Offset relatif terhadap periode berjalan hari ini.
    -- 0 = periode berjalan (MTD), 1 = bulan lalu, 2 = dua bulan lalu, dst.
    -- Dihitung ulang setiap dbt run, jadi otomatis bergeser tiap bulan.
    (SELECT seq FROM {{ ref('dim_current_period') }}) - seq AS periods_ago,
    channel,
    nsm_id, nsm_name,
    grsm_id, grsm_name,
    rsm_id, rsm_name,
    ss_id, ss_name,
    sbu_id, sbu_name,
    brand_id, brand_name,
    subbrand_id, subbrand_name,
    parent_id, parent_name,
    total_forecast,
    total_actual,
    -- LAG memberi baris sebelumnya di partisi, yang belum tentu seq-1 kalau
    -- ada periode bolong. Guard ini menyamakan perilakunya dengan LEFT JOIN
    -- lama: periode yang tidak persis seq-1 tetap menghasilkan NULL.
    CASE WHEN prev_seq = seq - 1 THEN prev_forecast END AS total_forecast_prev,
    CASE WHEN prev_seq = seq - 1 THEN prev_actual   END AS total_actual_prev
FROM lagged
