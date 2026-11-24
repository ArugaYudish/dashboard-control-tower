{{ config(
    materialized='table',
    indexes=[
      {'columns': ['year', 'week', 'distributor_id', 'pcode']}
    ]
) }}

select
  gsf.year,
  mc.period,
  gsf.week,
  '9999'::varchar          as wh_id,
  gsf.subdist_id           as distributor_id,
  gsf.kdbarang             as pcode,
  sum(gsf.so_awal_fdos)    as fdos_update,
  sum(gsf.so_awal_spk)     as alokasi,
  sum(gsf.so_awal_spo)     as spo,
  -- Billed qty across every SO type (FDOS + SPK + SPO), not FDOS-only.
  sum(gsf.qty_bill)        as qty_bill
from {{ ref('gold_sl_fdos') }} gsf
join spx.m_cycle2 mc
  on gsf.year = mc.year
 and gsf.week = mc.week
group by gsf.year, mc.period, gsf.week, gsf.subdist_id, gsf.kdbarang