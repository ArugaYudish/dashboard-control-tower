{{ config(
    materialized='table',
    indexes=[
      {'columns': ['week_year', 'distributor_id', 'pcode']}
    ]
) }}

with sl as (
  select
    s.year,
    s.week_num        as week,
    s.subdist_id      as distributor_id,
    s.kdbarang        as pcode,
    s.sbu_id,
    sum(s.so_awal_spo) as spo_qty,
    sum(s.so_awal_spk) as alokasi_qty   -- alokasi = SPK
  from {{ ref('gold_sl_fdos') }} s
  where s.week_num is not null
  group by s.year, s.week_num, s.subdist_id, s.kdbarang, s.sbu_id
),

src as (
  select
    f.week::int || '_' || f.year::int as week_year,
    f.sub_id                  as distributor_id,
    f.pcode,
    mp.div_id                 as sbu_id,
    f.qty_adj                 as fdosplan_qty,
    f.qty_adj * pr.price      as fdosplan_value,
    null::numeric             as fdosupd_qty,
    null::numeric             as fdosupd_value,
    null::numeric             as spo_qty,
    null::numeric             as spo_value,
    null::numeric             as alokasi_qty,
    null::numeric             as alokasi_value
  from spx.t_fdos_d2 f
  join spx.m_product mp     on mp.pcode = f.pcode
  left join spx.m_price pr  on pr.pcode = f.pcode and pr.ct_id = f.ct_id

  union all

  select
    u.week::int || '_' || u.year::int,
    u.distributor_id,
    u.pcode,
    mp.div_id,
    null, null,
    u.qty_adj,
    u.qty_adj * pr.price,
    null, null, null, null
  from spx.t_fdos_update_d u
  join spx.m_product mp     on mp.pcode = u.pcode
  left join spx.m_price pr  on pr.pcode = u.pcode and pr.ct_id = u.ct_id

  union all

  select
    sl.week || '_' || sl.year,
    sl.distributor_id,
    sl.pcode,
    sl.sbu_id,
    null, null, null, null,
    sl.spo_qty,
    sl.spo_qty * pr.price,
    sl.alokasi_qty,
    sl.alokasi_qty * pr.price
  from sl
  left join spx.m_distributor md on md.distributor_id = sl.distributor_id
  left join spx.m_price pr       on pr.pcode = sl.pcode and pr.ct_id = md.ct_id
)

select
  week_year,
  distributor_id,
  pcode,
  sbu_id,
  sum(fdosplan_qty)   as fdosplan_qty,
  sum(fdosplan_value) as fdosplan_value,
  sum(fdosupd_qty)    as fdosupd_qty,
  sum(fdosupd_value)  as fdosupd_value,
  sum(spo_qty)        as spo_qty,
  sum(spo_value)      as spo_value,
  sum(alokasi_qty)    as alokasi_qty,
  sum(alokasi_value)  as alokasi_value
from src
group by week_year, distributor_id, pcode, sbu_id
