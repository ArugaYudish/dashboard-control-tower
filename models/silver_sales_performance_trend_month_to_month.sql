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
    end as flag,'param' as param
  from spx.m_cycle3
  where year = extract(year from current_date)
  and period between 1 and extract(month from current_date)
),
product_hierarchy as (
  select distinct
    mp.div_id,      mdiv.div_nm,
    mp.brand_id,    mbrand.brand_nm,
    mp.subbrand_id, msubbrand.subbrand_nm,
    mp.parent_id,   mparent.parent_nm, 'param' as param
  from spx.m_product mp 
  left join spx.m_division  mdiv      on mdiv.div_id           = mp.div_id
  left join spx.m_brand     mbrand    on mbrand.brand_id       = mp.brand_id
  left join spx.m_subbrand  msubbrand on msubbrand.subbrand_id = mp.subbrand_id  and msubbrand.brand_id    = mp.brand_id
  left join spx.m_parent    mparent   on mparent.parent_id     = mp.parent_id
  where mp.ct_id ='120001' and mp.div_id <> 'XX'
),
fdis_actual as (
  select
    cw.period,
    cw.periodName,
    vfu.year,
    p.parent_id,
    sum(coalesce(vfu.fdis_actual,0)) as fdis_actual
  from spx.v_fdis_actual vfu
  join cycle_week cw
    on cw.year = vfu.year
   and cw.week = vfu.week  
  left join spx.m_product p
    on p.pcode = vfu.pcode
  group by cw.period, cw.periodName, vfu.year, p.parent_id
),
fdis_update as (
  select
    cw.period,
    cw.periodName,
    vfu.year,
    p.parent_id,
    sum(coalesce(vfu.fdis_update,0)) as fdis_update
  from spx.v_fdis_update vfu
  join cycle_week cw
    on cw.year = vfu.year
   and cw.week = vfu.week
  left join spx.m_product p
    on p.pcode = vfu.pcode
  group by cw.period, cw.periodName, vfu.year, p.parent_id
),
fdis as (
select  ph.parent_id, 
  cw.period, cw.periodName, cw.year,
    coalesce(fdis_update.fdis_update,0) as fdis_update, coalesce(fdis_actual.fdis_actual,0) as fdis_actual
  from product_hierarchy ph join (select distinct year, period, periodName, param from cycle_week) cw on ph.param = cw.param
left join fdis_update
  on fdis_update.parent_id = ph.parent_id and fdis_update.period = cw.period
  and fdis_update.year = cw.year 
left join fdis_actual  on fdis_actual.parent_id = ph.parent_id  
	and fdis_actual.period = cw.period and fdis_actual.year = cw.year
)
select channel, a.year, a.period, a.periodname, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name, 
	sbu_id, sbu_name, brand_id, brand_name, subbrand_id,subbrand_name,a.parent_id,parent_name,flag_sku,distributor_id,distributor_name,
	salfo_qty, salfo_value, stm_qty, stm_value, fdos_update, fdos_value, sta_qty, sta_value, fdis_update, fdis_actual
FROM
(select channel, ssp.year, ssp.period, ssp.periodname,nsm_id,nsm_name,grsm_id,grsm_name,rsm_id,rsm_name,ss_id,ss_name,sbu_id,sbu_name,brand_id,brand_name,subbrand_id,subbrand_name,ssp.parent_id,parent_name,flag_sku,distributor_id,distributor_name,
	sum(salfo_qty) as salfo_qty, SUM(salfo_value) as salfo_value, SUM(stm_qty) as stm_qty, SUM(stm_value) as stm_value,
	SUM(fdos_update) as fdos_update, SUM(fdos_value) as fdos_value, SUM(sta_qty) as sta_qty, SUM(sta_value) as sta_value	
from spx.silver_sales_performance_parent ssp 
	inner join cycle_week cw on ssp.year = cw.year and ssp.period = cw.period and ssp.week = cw.week
group by channel, ssp.year, ssp.period, ssp.periodname,nsm_id,nsm_name,grsm_id,grsm_name,rsm_id,rsm_name,ss_id,ss_name,sbu_id,sbu_name,brand_id,brand_name,subbrand_id,subbrand_name,ssp.parent_id,parent_name,flag_sku,distributor_id,distributor_name
) a 	
left join fdis on a.year = fdis.year and a.period = fdis.period and a.parent_id  = fdis.parent_id