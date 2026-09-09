{# Catat "kapan data week ini masuk ke Snopix BI" untuk satu sumber integrasi.

   Aturan intinya: HANYA week yang sedang berjalan yang boleh ditulis. Week yang sudah
   lewat tidak pernah disentuh lagi, sehingga tanggal integrasinya terkunci permanen.
   Itulah yang membuat setiap week punya timestamp berbeda -- bukan perbandingan isi
   data. Pendekatan `current_timestamp as loaded_at` di model biasa tidak bisa dipakai
   karena model di-full-refresh tiap build, sehingga seluruh week akan menampilkan
   waktu build terakhir.

   `_airbyte_extracted_at` juga tidak bisa dipakai: ketiga stream sumber full-refresh,
   jadi seluruh baris di seluruh week berbagi satu nilai identik per sync (terverifikasi
   2026-09-09: count(distinct _airbyte_extracted_at) = 1 pada STM, STA, dan STOCK).

   Argumen:
     source_code    'STM' | 'STA' | 'STOCK'
     relation       relasi sumber, mis. 'spx.v_sta_subdist'
     year_col       nama kolom tahun di relasi tsb (STM memakai 'tahun', bukan 'year')
     week_col       nama kolom week
     ts_col         kolom timestamp sumber, kalau ada. Hanya STM (`upload_date`) yang
                    punya; STA dan STOCK tidak, dan itu tidak masalah -- yang tampil ke
                    user adalah last_loaded_at. Kolom ini murni untuk diagnosa,
                    membedakan "telat di-upload di Snopix" vs "telat sampai di BI".
     lookback_weeks berapa week ke belakang yang masih boleh ikut diperbarui. 0 = hanya
                    week berjalan. Naikkan hanya kalau data sebuah week ternyata baru
                    tiba setelah week itu berakhir. #}

{% macro refresh_integration_watermark(source_code, relation, year_col, week_col, ts_col=none, lookback_weeks=0) %}

with wk as (
    -- Week fiskal diturunkan dari m_cycle3 (kalender harian), bukan dari date_trunc:
    -- penomoran week di sini milik bisnis, tidak harus sama dengan ISO week.
    -- `cdate <= current_date` membuatnya tetap benar kalau kalender belum terisi
    -- sampai hari ini -- yang terambil week terakhir yang sudah dimulai.
    select year::int as year, week::int as week,
           row_number() over (order by max(cdate) desc) as rn_desc
    from spx.m_cycle3
    where cdate::date <= current_date
    group by 1, 2
),
target_week as (
    select year, week from wk where rn_desc <= {{ lookback_weeks + 1 }}
),
cur as (
    -- JOIN, bukan LEFT JOIN: kalau week berjalan belum ada datanya sama sekali, CTE ini
    -- kosong, tidak ada baris yang ditulis, dan Superset tetap menampilkan '-'.
    --
    -- Join ke target_week sekaligus menyaring baris sampah di sumber: v_sta_subdist
    -- punya 10.815 baris ber-`year = 30` yang tidak akan pernah cocok dengan tahun
    -- week berjalan.
    select t.year,
           t.week,
           count(*) as row_count,
           {% if ts_col %} max(s.{{ ts_col }})::timestamp {% else %} null::timestamp {% endif %} as src_last_upload_at
    from target_week t
    join {{ relation }} s
      on s.{{ year_col }}::int = t.year
     and s.{{ week_col }}::int = t.week
    group by t.year, t.week
)
insert into spx.t_bi_integration_watermark as w
      (source_code, year, week, row_count, src_last_upload_at, first_loaded_at, last_loaded_at)
-- clock_timestamp(), bukan current_timestamp: post-hook berjalan di dalam transaksi
-- model, dan current_timestamp mengembalikan waktu MULAI transaksi. Untuk model seberat
-- silver_sales_performance_parent selisihnya bisa beberapa menit.
select '{{ source_code }}', year, week, row_count, src_last_upload_at,
       clock_timestamp()::timestamp, clock_timestamp()::timestamp
from cur
on conflict (source_code, year, week) do update
   set row_count          = excluded.row_count,
       src_last_upload_at = excluded.src_last_upload_at,
       last_loaded_at     = clock_timestamp()::timestamp;

{% endmacro %}
