{{ config(materialized='table') }}

with cycle_week as materialized (
  select distinct
    year,
    period,
    to_char(to_date(cast(period as text), 'MM'), 'Mon') as periodName,
    week,
    case
      when year = extract(year from current_date)     then 'cy'
      when year = extract(year from current_date) - 1 then 'ly'
    end as flag
  from spx.m_cycle3
  where (year * 12 + period)
    between (extract(year from current_date) * 12 + extract(month from current_date)) - 6
        and (extract(year from current_date) * 12 + extract(month from current_date))
),
product_hierarchy as (
  select distinct
    mp.div_id,      mdiv.div_nm,
    mp.brand_id,    mbrand.brand_nm,
    mp.subbrand_id, msubbrand.subbrand_nm,
    mp.parent_id,   mparent.parent_nm
  from spx.m_product mp
  left join spx.m_division  mdiv      on mdiv.div_id           = mp.div_id
  left join spx.m_brand     mbrand    on mbrand.brand_id       = mp.brand_id
  left join spx.m_subbrand  msubbrand on msubbrand.subbrand_id = mp.subbrand_id  and msubbrand.brand_id    = mp.brand_id
  left join spx.m_parent    mparent   on mparent.parent_id     = mp.parent_id
),
fdis as (
  select
    cw.period,
    cw.periodName,
    vfu.year,
    p.parent_id,
    sum(coalesce(vfu.fdis_update,0)) as fdis_update, sum(coalesce(vfa.fdis_actual,0)) as fdis_actual
  from spx.v_fdis_update vfu
  join cycle_week cw
    on cw.year = vfu.year
   and cw.week = vfu.week
  left join spx.v_fdis_actual vfa
    on  vfa.week   = vfu.week
    and vfa.period = cw.period
    and vfa.year   = vfu.year
    and vfa.wh_id  = vfu.wh_id
    and vfa.pcode  = vfu.pcode
  left join spx.m_product p
    on p.pcode = vfu.pcode
  group by cw.period, cw.periodName, vfu.year, p.parent_id
),
fdos as (
  select
    sta.period,
    sta.year,
    sta.parent_id,
    sum(coalesce(fdos.fdos_update,0)) as fdos_update, sum(coalesce(sta.sta_qty,0)) as sta_qty
  from (
    select
      cw.period, mss.year, mp.parent_id, mss.week, mss.distributor_id,
      sum(mss.sta_qty) as sta_qty
    from spx.m_sta_subdist mss
    join cycle_week cw
      on cw.year = mss.year and cw.week = mss.week
    left join spx.m_product mp
      on mp.pcode = mss.pcode
    group by cw.period, mss.year, mp.parent_id, mss.week, mss.distributor_id
  ) sta
  left join (
    select
      vfu.period, vfu.year, mp.parent_id, vfu.week, vfu.distributor_id,
      sum(vfu.fdos_update) as fdos_update
    from spx.v_fdos_update vfu
    join cycle_week cw
      on cw.year = vfu.year and cw.week = vfu.week
    left join spx.m_product mp
      on mp.pcode = vfu.pcode
    group by vfu.period, vfu.year, mp.parent_id, vfu.week, vfu.distributor_id
  ) fdos
    on  fdos.week           = sta.week
    and fdos.period         = sta.period
    and fdos.year           = sta.year
    and fdos.distributor_id = sta.distributor_id
    and fdos.parent_id      = sta.parent_id
  group by sta.period, sta.year, sta.parent_id
),
sales as
(
  select year, period, parent_id, sum(coalesce(salfo_qty,0)) as salfo_qty, sum(coalesce(stm_qty,0)) as stm_qty  
   from spx.silver_sales_performance ssp 
  group by year, period, parent_id
)
select
  ph.div_id as sbu_id, ph.div_nm as sbu_name,
  ph.brand_id, ph.brand_nm as brand_name,
  ph.subbrand_id, ph.subbrand_nm as subbrand_name,
  ph.parent_id, ph.parent_nm as parent_name,
  fdis.period, fdis.periodName, fdis.year,
  coalesce(fdis.fdis_update,0) as fdis_update, coalesce(fdis.fdis_actual,0) as fdis_actual,  
  coalesce(fdos.fdos_update,0) as fdos_update, coalesce(fdos.sta_qty,0) as sta_qty, 
  coalesce(sales.salfo_qty,0) as salfo_qty, coalesce(sales.stm_qty,0) as stm_qty
from product_hierarchy ph
join fdis
  on fdis.parent_id = ph.parent_id
left join fdos
  on  fdos.parent_id = fdis.parent_id
  and fdos.period    = fdis.period
  and fdos.year      = fdis.year
left join sales
	on sales.parent_id = fdis.parent_id
	and cast(sales.period as numeric) = fdis.period
	and cast(sales.year as numeric) = fdis.year