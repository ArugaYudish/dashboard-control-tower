{{
    config(
        materialized='view',
        alias='v_monitoring_closing_subdist_weekly'
    )
}}

-- Monitoring Closing Weekly Subdist untuk dashboard SCCT.
--
-- Aturan bisnis: untuk filter week W, yang dievaluasi adalah closing di hari Sabtu week W-1.
-- Sebuah subdist dianggap sudah closing bila `ext_date = Sabtu W-1` ATAU
-- `next_date > Sabtu W-1`. Contoh dari requirement: filter week 37 -> Sabtu 5 September 2026.
--
-- Requirement menyebut `upd_date`, tapi kolom itu tidak dipakai: pada subdist aktif nilainya
-- basi bertahun-tahun (mis. 2024-10-29 dan 2025-06-04 pada subdist yang aktif per September
-- 2026), jadi ia tanggal update record master, bukan tanggal closing. Yang dipakai `ext_date`
-- -- tanggal bisnis terakhir yang sudah ditutup. Karena closing dijalankan malam hari,
-- `next_date` adalah hari berikutnya yang masih terbuka; keduanya selalu berdampingan.
--
-- BATASAN YANG DITERIMA SADAR: spx.m_ho_subdist adalah master state terkini (PK subdist_id,
-- tanpa kolom year/week), jadi evaluasi ini hanya sahih untuk week terkini. Untuk week yang
-- sudah lama lewat, `next_date > Sabtu W-1` otomatis benar sehingga angkanya cenderung
-- mendekati 100% dan berubah tiap hari. Kalau angka historis dibutuhkan, jalan keluarnya
-- tabel snapshot mingguan dengan pola penguncian yang sama seperti t_bi_integration_watermark.

{# Stream Airbyte logistic.m_ho_subdist -> spx.m_ho_subdist belum dibuat. Selama tabelnya
   belum ada, view tetap terbangun dengan stub kosong supaya `dbt build` tidak gagal; query
   Superset yang berbentuk agregat tanpa GROUP BY tetap mengembalikan satu baris (0/0).
   Begitu stream-nya jalan, build berikutnya otomatis memakai tabel aslinya. #}
{% set ho_rel = adapter.get_relation(
       database=target.database, schema='spx', identifier='m_ho_subdist') %}

with wk as (
    -- Jendela sengaja dimundurkan satu tahun ekstra supaya week paling awal di rentang
    -- dashboard tetap punya W-1 untuk dijoin.
    select year::int as year,
           week::int as week,
           row_number() over (order by min(cdate)) as rn
    from spx.m_cycle3
    where year between extract(year from current_date) - 2
                   and extract(year from current_date)
    group by 1, 2
),
sabtu as (
    -- Sabtu diambil dari kalender, bukan dihitung dari week_end. Terverifikasi 2026-09-09:
    -- 521 dari 521 week fiskal berakhir hari Minggu dan tiap week tepat 7 hari (3.647/521),
    -- jadi setiap week punya persis satu Sabtu.
    select year::int as year,
           week::int as week,
           cdate::date as sabtu_date
    from spx.m_cycle3
    where extract(dow from cdate) = 6          -- 6 = Sabtu
),
target as (
    -- Filter week W -> evaluasi Sabtu di week W-1. Dijembatani lewat rn, bukan `week - 1`,
    -- supaya pergantian tahun (week 1 -> week 52 tahun sebelumnya) tetap benar.
    select w.year as filter_year,
           w.week as filter_week,
           p.year as eval_year,
           p.week as eval_week,
           s.sabtu_date
    from wk w
    join wk p    on p.rn = w.rn - 1
    join sabtu s on s.year = p.year and s.week = p.week
    where w.year between extract(year from current_date) - 1
                     and extract(year from current_date)
),
active_subdist as (
{%- if ho_rel %}
    -- Ditulis negatif (<> 'Non Aktif'), bukan = 'Aktif': data sumber mengandung typo 'Akif',
    -- sehingga tes positif akan mengembalikan nol baris.
    select subdist_id  as distributor_id,
           subdist_nm  as distributor_nm,
           ext_date,
           next_date,
           upd_date
    from spx.m_ho_subdist
    where coalesce(flag_subdist, '') <> 'Non Aktif'
{%- else %}
    select null::varchar as distributor_id,
           null::varchar as distributor_nm,
           null::date    as ext_date,
           null::date    as next_date,
           null::date    as upd_date
    where false
{%- endif %}
),
coverage as (
    -- v_sales_hierarchy memetakan distributor -> ss/rsm/grsm/nsm secara langsung.
    -- Satu distributor bisa berada di bawah lebih dari satu ss (1.535 baris untuk 1.061
    -- distributor), jadi chart WAJIB memakai count(distinct distributor_id), bukan count(*).
    select distinct distributor_id, ss_id, rsm_id, grsm_id, nsm_id
    from spx.v_sales_hierarchy
)

-- Chart Superset (satu virtual dataset untuk kartu "Completion Rate Subdist"):
--
--   select count(distinct distributor_id) filter (where closed_flag = 1) as closed,
--          count(distinct distributor_id)                                as total,
--          round(100.0 * count(distinct distributor_id) filter (where closed_flag = 1)
--                / nullif(count(distinct distributor_id), 0), 0)         as pct
--   from spx.v_monitoring_closing_subdist_weekly
--   where year = {{ "{{ url_param('year') }}" }}::int
--     and week = {{ "{{ url_param('week') }}" }}::int
--     and ss_id in ( ...url_param('ssId') dipecah dari CSV... )
select t.filter_year as year,
       t.filter_week as week,
       -- Week yang sebenarnya dievaluasi (W-1) beserta tanggal Sabtunya, supaya angka di
       -- dashboard bisa ditelusuri balik tanpa menebak.
       t.eval_year,
       t.eval_week,
       t.sabtu_date,
       c.ss_id,
       c.rsm_id,
       c.grsm_id,
       c.nsm_id,
       a.distributor_id,
       a.distributor_nm,
       -- m_ho_subdist tidak membawa channel, sedangkan dashboard punya filter channel.
       md.sls_div as channel,
       -- Ketiganya diekspos supaya angka di dashboard bisa ditelusuri balik per subdist.
       -- upd_date ikut dibawa untuk diagnosa, tapi tidak dipakai menghitung closed_flag.
       a.ext_date,
       a.next_date,
       a.upd_date,
       case when a.ext_date   = t.sabtu_date
                 or a.next_date > t.sabtu_date
            then 1 else 0 end as closed_flag
from target t
cross join active_subdist a
join coverage c on c.distributor_id = a.distributor_id
left join spx.m_distributor md on md.distributor_id = a.distributor_id
