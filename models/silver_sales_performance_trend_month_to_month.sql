{{ config(
    materialized='table',
    pre_hook="set local work_mem = '256MB'",
    indexes=[
      {'columns': ['year', 'period', 'channel', 'parent_id', 'distributor_id']}
    ]
) }}

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
  -- Periode berjalan = periode dari tanggal kalender terakhir yang <= hari ini.
  -- Bentuk lama `where cdate = current_date` mengembalikan NULL (-> model kosong)
  -- kalau hari ini tidak ada di m_cycle3, dan error kalau cdate-nya lebih dari
  -- satu baris. max(...) <= current_date aman untuk kedua kasus.
  and period between 1 and (
        select max(period)
        from spx.m_cycle3
        where cdate::date <= current_date
          and year = extract(year from current_date)
      )
),
-- Dari CTE ini yang dipakai hilir cuma parent_id (+ param untuk cross join):
-- div_nm / brand_nm / subbrand_nm / parent_nm tidak pernah diselect di mana pun,
-- jadi 4 LEFT JOIN master dan 8 kolomnya dibuang.
--
-- Efek samping yang disengaja: dulu DISTINCT-nya atas (div, brand, subbrand,
-- parent) sehingga satu parent_id bisa muncul lebih dari sekali kalau parent-nya
-- tersebar di beberapa brand/subbrand -- dan setiap duplikat itu menggandakan
-- baris hasil akhir lewat `left join fdis ... on a.parent_id = fdis.parent_id`.
-- DISTINCT atas parent_id saja menutup celah itu.
parent_scope as (
  select distinct mp.parent_id, 'param' as param
  from spx.m_product mp
  where mp.ct_id = '120001'
    and mp.div_id <> 'XX'
    and mp.parent_id is not null
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
fdos_plan as 
(
	select vfpw.year, cw.period, p.parent_id, vfpw.distributor_id, sum(qty) as fdos_plan 
	from spx.v_fdos_plan_weekly vfpw
		join cycle_week cw
	    on cw.year = vfpw.year
	   and cw.week = vfpw.week
	left join spx.m_product p
	    on p.pcode = vfpw.pcode
	group by vfpw.year, cw.period, p.parent_id, vfpw.distributor_id
),
fdis_plan as 
(
	SELECT h.year, h.period, p.parent_id , sum(qty_final) as fdis_plan
	FROM spx.t_fdis_marketing_h h 
	 join cycle_week cw
	    on cw.year = h.year
	   and cw.period = h.period  
	  left join spx.m_product p
	    on p.pcode = h.pcode
	WHERE (h.year * 12 + h.period) = (year_upload * 12 + period_upload) + 1
	group by h.year, h.period, p.parent_id
),
fdis as (
select  ph.parent_id, 
  cw.period, cw.periodName, cw.year,
    coalesce(fdis_update.fdis_update,0) as fdis_update, coalesce(fdis_actual.fdis_actual,0) as fdis_actual,
    coalesce(fdis_plan.fdis_plan,0) as fdis_plan
  from parent_scope ph join (select distinct year, period, periodName, param from cycle_week) cw on ph.param = cw.param
left join fdis_update
  on fdis_update.parent_id = ph.parent_id and fdis_update.period = cw.period
  and fdis_update.year = cw.year 
left join fdis_actual  on fdis_actual.parent_id = ph.parent_id  
	and fdis_actual.period = cw.period and fdis_actual.year = cw.year
left join fdis_plan  on fdis_plan.parent_id = ph.parent_id  
	and fdis_plan.period = cw.period and fdis_plan.year = cw.year	
)
select channel, a.year, a.period, a.periodname, nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name, 
	sbu_id, sbu_name, brand_id, brand_name, subbrand_id,subbrand_name,a.parent_id,parent_name,flag_sku,distributor_id,distributor_name,
	salfo_qty, salfo_value, stm_qty, stm_value, fdos_update, fdos_value, sta_qty, sta_value, fdis_update, fdis_actual, fdis_plan, fdos_plan
FROM
(select channel, ssp.year, ssp.period, ssp.periodname,nsm_id,nsm_name,grsm_id,grsm_name,rsm_id,rsm_name,ss_id,ss_name,sbu_id,sbu_name,brand_id,brand_name,subbrand_id,subbrand_name,ssp.parent_id,parent_name,flag_sku,
	ssp.distributor_id,distributor_name,
	sum(salfo_qty) as salfo_qty, SUM(salfo_value) as salfo_value, SUM(stm_qty) as stm_qty, SUM(stm_value) as stm_value,
	SUM(fdos_update) as fdos_update, SUM(fdos_value) as fdos_value, SUM(sta_qty) as sta_qty, SUM(sta_value) as sta_value, 
	SUM(fdos_plan.fdos_plan) as fdos_plan
from spx.silver_sales_performance_parent ssp 
	inner join cycle_week cw on ssp.year = cw.year and ssp.period = cw.period and ssp.week = cw.week
	left join fdos_plan on ssp.year = fdos_plan.year and ssp.period = fdos_plan.period and ssp.parent_id = fdos_plan.parent_id and ssp.distributor_id = fdos_plan.distributor_id
group by channel, ssp.year, ssp.period, ssp.periodname,nsm_id,nsm_name,grsm_id,grsm_name,rsm_id,rsm_name,ss_id,ss_name,sbu_id,sbu_name,brand_id,
brand_name,subbrand_id,subbrand_name,ssp.parent_id,parent_name,flag_sku,ssp.distributor_id,distributor_name
) a 	
left join fdis on a.year = fdis.year and a.period = fdis.period and a.parent_id  = fdis.parent_id