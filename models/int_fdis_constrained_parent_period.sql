{{ config(
    materialized='table',
    indexes=[
      {'columns': ['year', 'period', 'parent_id'], 'unique': True}
    ]
) }}

-- Flag FDIS constrained NASIONAL per (year, period, parent_id).
--
-- Dipakai gold_forecast_kpi_by_period (gold_forecast_kpi_detail.sql): flag ditempel ke
-- setiap baris gold, lalu total_forecast_constrained = total_actual bila constrained.
-- Yang ditempel adalah FLAG, bukan nilai FDIS untuk dijumlahkan. FDIS tidak punya
-- distributor/salesman (t_fdis_* ber-key wh_id/buyer_id/plant_id), jadi nilainya hanya
-- bermakna di level nasional per parent.
--
-- Aturan (spec, dibawa ke level parent karena gold hanya sampai parent_id):
--   constrained  <=>  FDIS Confirm (M-1) < MIN(SALFO, FDIS Plan)
--
-- Model ini TIDAK boleh ref ke gold_forecast_kpi_detail (gold ref ke model ini).

with
-- FDIS Plan: angka marketing (t_fdis_marketing_h.qty_final) didahulukan, kalau tidak ada
-- baru t_fdis_plan_h.qty. Keduanya tahap berurutan untuk baris yang sama, tetapi plan_h
-- memakai sls_div = 'ALL' sedangkan marketing_h memakai GT/MT -- jadi sls_div TIDAK boleh
-- jadi kunci join (dengan sls_div, keduanya tidak pernah match dan ikut terjumlah dua kali).
-- buyer_id juga dilepas: di kedua tabel hanya ada B0001.
--
-- M-1 = lead_months 1: di-upload di bulan sebelum bulan target. Tidak ada lead 0 di data.
plan_mkt as (
  select year_upload, period_upload, year, period, wh_id, plant_id, pcode,
         sum(qty_final) as qty
  from spx.t_fdis_marketing_h
  where (year * 12 + period) - (year_upload * 12 + period_upload) = 1
    and year >= extract(year from current_date) - 1
  group by year_upload, period_upload, year, period, wh_id, plant_id, pcode
),
plan_h as (
  select year_upload, period_upload, year, period, wh_id, plant_id, pcode,
         sum(qty) as qty
  from spx.t_fdis_plan_h
  where (year * 12 + period) - (year_upload * 12 + period_upload) = 1
    and year >= extract(year from current_date) - 1
  group by year_upload, period_upload, year, period, wh_id, plant_id, pcode
),
fdis_plan as (
  -- pcode -> parent_id lewat m_product: 1 pcode = 1 parent (diverifikasi), jadi tidak
  -- ada fan-out. pg_id tidak perlu di sini karena grain akhirnya parent, bukan product group.
  select k.year::int as year, k.period::int as period, mp.parent_id,
         sum(k.qty) as fdis_plan
  from (
    select coalesce(m.year,   p.year)   as year,
           coalesce(m.period, p.period) as period,
           coalesce(m.pcode,  p.pcode)  as pcode,
           coalesce(m.qty,    p.qty)    as qty
    from plan_mkt m
    full outer join plan_h p
      on  p.year_upload   = m.year_upload
      and p.period_upload = m.period_upload
      and p.year          = m.year
      and p.period        = m.period
      and p.wh_id         = m.wh_id
      and p.plant_id      = m.plant_id
      and p.pcode         = m.pcode
  ) k
  join spx.m_product mp on mp.pcode = k.pcode
  where mp.parent_id is not null
  group by k.year, k.period, mp.parent_id
),

-- FDIS Confirm (M-1): t_upload_fdis_confirm, target per MINGGU -> periode lewat m_cycle3
-- (tidak ada minggu yang terbelah dua periode di 2025-2027, jadi (year, week) -> period 1:1).
-- Tabel ini juga berisi upload ekspor (MY, TH, CN, ...); hanya domestik yang dipakai,
-- sama dengan buyer B0001 di FDIS plan. qty_adj = qty di semua baris saat ini, tapi
-- qty_adj didahulukan kalau suatu saat diisi berbeda.
cycle_week as (
  select distinct year, week, period
  from spx.m_cycle3
  where year >= extract(year from current_date) - 1
),
fdis_confirm as (
  select cw.year::int as year, cw.period::int as period, mp.parent_id,
         sum(coalesce(c.qty_adj, c.qty)) as fdis_confirm
  from spx.t_upload_fdis_confirm c
  join cycle_week cw
    on cw.year = c.year and cw.week = c.week
  join spx.m_product mp on mp.pcode = c.pcode
  where c.country_code = 'ID'
    and c.buyer_code   = 'B0001'
    and (cw.year * 12 + cw.period) - (c.year_upload * 12 + c.period_upload) = 1
    and mp.parent_id is not null
  group by cw.year, cw.period, mp.parent_id
),

-- SALFO penuh sebulan: semua minggu, TANPA filter stm <> 0 dan tanpa gerbang minggu
-- berjalan seperti di gold. Sengaja: saat barang kurang, penjualan bisa 0 dan filter stm
-- akan membuang salfo justru di slice yang terdampak, sehingga demand terlihat kecil.
salfo as (
  select year::int as year, period::int as period, parent_id,
         sum(salfo_qty) as salfo_national
  from {{ ref('silver_sales_performance_parent') }}
  where parent_id is not null
  group by year, period, parent_id
),

spine as (
  select year, period, parent_id from fdis_plan
  union
  select year, period, parent_id from fdis_confirm
  union
  select year, period, parent_id from salfo
)

select
  s.year,
  s.period,
  s.parent_id,
  fp.fdis_plan,
  fc.fdis_confirm,
  sa.salfo_national,
  -- CASE eksplisit, bukan sekadar `confirm < LEAST(...)`: LEAST di Postgres mengabaikan
  -- NULL (LEAST(NULL, 5) = 5). Data FDIS yang tidak ada bukan bukti constraint; membacanya
  -- sebagai constrained/0 akan menaikkan FA secara palsu.
  case
    when fp.fdis_plan is null
      or fc.fdis_confirm is null
      or sa.salfo_national is null then false
    else fc.fdis_confirm < least(sa.salfo_national, fp.fdis_plan)
  end as is_constrained
from spine s
left join fdis_plan    fp on fp.year = s.year and fp.period = s.period and fp.parent_id = s.parent_id
left join fdis_confirm fc on fc.year = s.year and fc.period = s.period and fc.parent_id = s.parent_id
left join salfo        sa on sa.year = s.year and sa.period = s.period and sa.parent_id = s.parent_id
