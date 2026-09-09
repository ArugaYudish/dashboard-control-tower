{{
    config(
        materialized='view',
        alias='v_monitoring_closing_subdist_weekly'
    )
}}

{# spx.t_subdist_weekly_closing datang dari stream Airbyte yang belum dibuat. Selama
   tabelnya belum ada, view tetap dibangun dengan stub kosong sehingga seluruh subdist
   tampil closing_flag = '0' (progress 0/N) alih-alih membuat `dbt build` gagal. Begitu
   stream-nya jalan, build berikutnya otomatis memakai tabel aslinya -- tidak ada yang
   perlu diubah di file ini. #}
{% set closing_rel = adapter.get_relation(
       database=target.database, schema='spx', identifier='t_subdist_weekly_closing') %}

with wk as (
    -- Cutoff = Senin siang W+1, diturunkan dari m_cycle3 dan bukan diasumsikan.
    -- (Terverifikasi 2026-09-09: 521 dari 521 week fiskal memang berakhir hari Minggu,
    -- tapi menurunkannya dari kalender tetap lebih aman daripada meng-hardcode DOW.)
    --
    -- Filter tahun WAJIB: m_cycle3 memuat ~521 week (10 tahun). Tanpa filter, spine
    -- wk x active_dist membengkak ~5x dari yang dibutuhkan dashboard.
    select year::int as year,
           week::int as week,
           max(cdate)::timestamp + interval '1 day' + interval '12 hour' as cutoff_at
    from spx.m_cycle3
    where year between extract(year from current_date) - 1
                   and extract(year from current_date)
    group by 1, 2
),
active_dist as (
    -- spx.m_distributor_integrasi (idiom yang dipakai service Snopix) tidak direplikasi
    -- ke BI, jadi "aktif" memakai m_distributor.flag: '1' = aktif (1.185), '0' = nonaktif
    -- (424). Dampaknya ke penyebut kecil sekali -- dari 1.061 distributor yang ter-cover
    -- hierarki, filter ini hanya membuang 2, menyisakan 1.059.
    select d.distributor_id, d.distributor_nm, d.sls_div as channel
    from spx.m_distributor d
    where d.flag = '1'
),
coverage as (
    -- v_sales_hierarchy sudah memetakan distributor -> ss/rsm/grsm/nsm secara langsung,
    -- jadi tidak perlu lewat m_emp_team. Menjoin keduanya justru fan-out: m_emp_team dan
    -- v_sales_hierarchy sama-sama punya distributor_id, dan join lewat emp_id = ss_id
    -- tidak mengikat kolom itu.
    --
    -- Satu distributor bisa muncul di bawah lebih dari satu ss (1.535 baris untuk 1.061
    -- distributor), jadi chart harus memakai count(distinct distributor_id), bukan
    -- count(*) -- lihat contoh query di bawah.
    select distinct distributor_id, ss_id, rsm_id, grsm_id, nsm_id
    from spx.v_sales_hierarchy
),
closing as (
{%- if closing_rel %}
    select year::int as year,
           week::int as week,
           distributor_id,
           closing_flag,
           closing_date
    from spx.t_subdist_weekly_closing
{%- else %}
    select null::int       as year,
           null::int       as week,
           null::varchar   as distributor_id,
           null::char(1)   as closing_flag,
           null::timestamp as closing_date
    where false
{%- endif %}
)

-- Chart Superset:
--
--   select count(distinct distributor_id) filter (where closing_flag = '1') as closed,
--          count(distinct distributor_id)                                   as total,
--          round(100.0 * count(distinct distributor_id) filter (where closing_flag = '1')
--                / nullif(count(distinct distributor_id), 0), 1)            as pct
--   from spx.v_monitoring_closing_subdist_weekly
--   where year = {{ "{{ url_param('year') }}" }}::int
--     and week = {{ "{{ url_param('week') }}" }}::int
--     and ss_id in ( ...url_param('ssId') dipecah dari CSV... )
--
-- Dua ukuran disediakan: closing_flag (sudah closing, kapan pun) yang dipakai requirement
-- saat ini, dan closed_on_time (closing sebelum cutoff Senin siang W+1) yang disiapkan
-- karena requirement menyebut cutoff dan kemungkinan akan diminta menyusul.
select wk.year,
       wk.week,
       c.ss_id,
       c.rsm_id,
       c.grsm_id,
       c.nsm_id,
       a.distributor_id,
       a.distributor_nm,
       a.channel,
       coalesce(cl.closing_flag, '0') as closing_flag,
       cl.closing_date,
       wk.cutoff_at,
       case when cl.closing_flag = '1'
                 and cl.closing_date is not null
                 and cl.closing_date <= wk.cutoff_at
            then 1 else 0 end as closed_on_time
from wk
cross join active_dist a
join coverage c on c.distributor_id = a.distributor_id
left join closing cl
       on cl.year           = wk.year
      and cl.week           = wk.week
      and cl.distributor_id = a.distributor_id
