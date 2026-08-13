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
      {'columns': ['distributor_id']},
      {'columns': ['channel']}
    ]
) }}

WITH open_weeks AS (
    -- Minggu yang belum tutup: minggu berjalan + semua minggu ke depan.
    -- Dipakai HANYA untuk mengklasifikasi minggu, bukan untuk membuang minggu.
    -- Minggu berjalan tetap ada di tabel, hanya saja disaring (lihat `scoped`).
    SELECT year, week
    FROM spx.m_cycle3
    GROUP BY year, week
    HAVING MAX(cdate::date) >= CURRENT_DATE
),

scoped AS (
    -- Minggu yang SUDAH tutup: semua baris ikut apa adanya, tanpa gerbang.
    -- Slice yang punya salfo tapi tidak menjual apa pun adalah forecast miss
    -- yang sebenarnya, jadi harus tetap menekan FA. Menyaringnya justru
    -- menaikkan FA secara semu.
    SELECT s.year, s.period, s.channel,
           s.nsm_id, s.nsm_name, s.grsm_id, s.grsm_name,
           s.rsm_id, s.rsm_name, s.ss_id, s.ss_name,
           s.distributor_id, s.distributor_name,
           s.sbu_id, s.sbu_name, s.brand_id, s.brand_name,
           s.subbrand_id, s.subbrand_name, s.parent_id, s.parent_name,
           s.salfo_qty, s.stm_qty
    FROM {{ ref('silver_sales_performance_parent') }} s
    WHERE NOT EXISTS (
        SELECT 1 FROM open_weeks ow
        WHERE ow.year = s.year AND ow.week = s.week
    )

    UNION ALL

    -- Minggu BERJALAN: stm masih menetes masuk, jadi salfo hanya dihitung untuk
    -- slice yang sudah mencatat stm di minggu itu.
    --
    -- Gerbang versi pertama memakai grain (year, period, week, parent_id) dan
    -- terlalu longgar: pertanyaannya "apakah parent ini punya stm di minggu itu,
    -- di mana pun", bukan "apakah slice ini punya stm". Satu baris saudara di
    -- distributor/channel/product-group lain menghidupkan minggu itu untuk
    -- SELURUH slice parent tsb. Kasus nyata parent 100090 (MALKIST ABON FAM
    -- PACK) 2026 P8: total_forecast 110,76 = 55,76 (mg31) + 55 (mg32) padahal
    -- slice GT/ss 102008 tidak punya stm sama sekali di mg32.
    --
    -- PARTITION BY bersifat NULL-safe. Itu penting karena nsm/grsm/rsm/ss dan
    -- sbu/brand/subbrand semuanya nullable -- equi-join di sini akan butuh
    -- IS NOT DISTINCT FROM, predikat non-hashable yang penghapusannya membawa
    -- model ini dari 43 menit jadi hitungan detik.
    SELECT t.year, t.period, t.channel,
           t.nsm_id, t.nsm_name, t.grsm_id, t.grsm_name,
           t.rsm_id, t.rsm_name, t.ss_id, t.ss_name,
           t.distributor_id, t.distributor_name,
           t.sbu_id, t.sbu_name, t.brand_id, t.brand_name,
           t.subbrand_id, t.subbrand_name, t.parent_id, t.parent_name,
           t.salfo_qty, t.stm_qty
    FROM (
        SELECT s.*,
               SUM(s.stm_qty) OVER (
                   PARTITION BY s.year, s.period, s.week, s.channel,
                                s.nsm_id, s.grsm_id, s.rsm_id, s.ss_id,
                                s.distributor_id,
                                s.sbu_id, s.brand_id, s.subbrand_id, s.parent_id
               ) AS slice_week_stm
        FROM {{ ref('silver_sales_performance_parent') }} s
        WHERE EXISTS (
            SELECT 1 FROM open_weeks ow
            WHERE ow.year = s.year AND ow.week = s.week
        )
    ) t
    WHERE t.slice_week_stm IS NOT NULL
),

agg AS (
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
    --
    -- distributor_id menyusul sebagai kunci grouping. Silver sudah bergrain
    -- distributor, jadi ini hanya memecah baris yang sudah ada -- total_forecast
    -- dan total_actual identik kalau di-agregasi ulang tanpa distributor.
    -- distributor_name aman ikut pola MIN(name) yang sama: silver mengambilnya
    -- lewat join langsung ke spx.m_distributor pada distributor_id, jadi
    -- dependensi fungsionalnya by construction, bukan kebetulan data.
    --
    -- total_actual tidak berubah sedikit pun oleh gerbang di `scoped`: minggu
    -- tutup tidak disaring sama sekali, dan di minggu berjalan setiap baris
    -- dengan stm_qty non-NULL pasti punya slice_week_stm non-NULL juga. Jadi
    -- tidak ada aktual yang bisa terbuang -- yang berkurang hanya total_forecast.
    SELECT
        year::int   AS year,
        period::int AS period,
        channel,
        nsm_id, grsm_id, rsm_id, ss_id, distributor_id,
        sbu_id, brand_id, subbrand_id, parent_id,
        MIN(nsm_name)      AS nsm_name,
        MIN(grsm_name)     AS grsm_name,
        MIN(rsm_name)      AS rsm_name,
        MIN(ss_name)       AS ss_name,
        MIN(distributor_name) AS distributor_name,
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
    FROM scoped
    GROUP BY
        year, period, channel,
        nsm_id, grsm_id, rsm_id, ss_id, distributor_id,
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
                     s.distributor_id,
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
    distributor_id, distributor_name,
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
