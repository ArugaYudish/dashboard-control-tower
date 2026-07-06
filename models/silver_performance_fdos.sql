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
  where year between extract(year from current_date) - 1
                 and extract(year from current_date)
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
sta as 
(
	select mss.year, cw.period, mss.week, mss.distributor_id, mp.parent_id, cw.flag,  SUM(mss.sta_qty) as sta_qty, SUM(mss.sta_value) as sta_value
		from spx.m_sta_subdist mss inner join cycle_week cw on mss.year = cw.year and mss.week = cw.week 
		inner join spx.m_product mp on mss.pcode = mp.pcode
	group by mss.year, cw.period, mss.week, mss.distributor_id, mp.parent_id, cw.flag
),
fdos as
(
  SELECT a.year, a.period, a.week, a.distributor_id, a.parent_id, SUM(a.fdos_update) as fdos_update, SUM(a.fdos_value) as fdos_value
  FROM ( 
select vfu.year, vfu.period, vfu.week, vfu.distributor_id, mp.pcode, mp.parent_id, vfu.fdos_update, vfu.fdos_update * coalesce(mpd.price,0) as fdos_value 
   from spx.v_fdos_update vfu 
 	inner join cycle_week cw on vfu.year = cw.year and vfu.period = cw.period and vfu.week = cw.week
	inner join spx.m_product mp on vfu.pcode = mp.pcode
  inner join spx.m_distributor md on vfu.distributor_id = md.distributor_id
  left join spx.m_price_divisi mpd on vfu.pcode = mpd.pcode and vfu.year = mpd.year and md.sls_div = mpd.sls_div
 ) a
 GROUP BY a.year, a.period, a.week, a.distributor_id, a.parent_id
),
sales_hir as 
(
select distinct parent_id, ss_id, nsm_id, rsm_id, grsm_id, ss_name, nsm_name, rsm_name, grsm_name, distributor_id 
 from spx.v_sales_hierarchy_product vshp 
 left join spx.m_product ph on vshp.pcode = ph.pcode
)
select md.sls_div as channel, sta.year, sta.period, sta.week, sta.flag, vsh.nsm_id, vsh.nsm_name, vsh.grsm_id, vsh.grsm_name, vsh.rsm_id, vsh.rsm_name, vsh.ss_id, vsh.ss_name,
	sta.distributor_id, sta.parent_id, coalesce(sta.sta_qty,0) as sta_qty, coalesce(sta.sta_value,0) as sta_value, coalesce(fdos.fdos_update,0) as fdos_update, coalesce(fdos.fdos_value,0) as fdos_value
 from sta 
 left join fdos on sta.year = fdos.year and sta.period = fdos.period and sta.week = fdos.week 
	and sta.distributor_id = fdos.distributor_id and sta.parent_id = fdos.parent_id 
 left join sales_hir vsh on sta.distributor_id = vsh.distributor_id and sta.parent_id = vsh.parent_id
 left join spx.m_distributor md ON sta.distributor_id = md.distributor_id