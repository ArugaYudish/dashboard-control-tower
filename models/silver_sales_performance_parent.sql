{{ config(materialized='table') }}

with cycle_ranked as (
  select year, week, period,
         min(cdate) as week_start,
         max(cdate) as week_end,
         row_number() over (order by min(cdate)) as rn,
         case when year = EXTRACT(YEAR FROM CURRENT_DATE) then 'cy'
  		 when year = EXTRACT(YEAR FROM CURRENT_DATE) -1 then 'ly'
  	end as flag
  from spx.m_cycle3
  where year between extract(year from current_date) - 1
                 and extract(year from current_date)
  group by year, week, period
),
cur as (
  select rn as cur_rn
  from cycle_ranked
  where week_start <= current_date
  order by week_start desc
  limit 1
),
window_weeks as (
  select cr.year, cr.week,
         (cr.rn between cur.cur_rn - 6  and cur.cur_rn - 2) as in_5w,
         (cr.rn between cur.cur_rn - 14 and cur.cur_rn - 2) as in_13w
  from cycle_ranked cr
  cross join cur
  where cr.rn between cur.cur_rn - 14 and cur.cur_rn - 2
),
sales_hierarchy as (
	select distinct mp.parent_id, vshp.ss_id, vshp.nsm_id, vshp.rsm_id , vshp.grsm_id, ss_name, nsm_name, rsm_name, grsm_name, distributor_id 
	 from spx.v_sales_hierarchy_product vshp left join spx.m_product mp on vshp.pcode = mp.pcode	
),
salfo as (
	select year, week, parent_id, distributor_id, sum(qty) as salfo_qty, sum(salfo_value) as salfo_value
	from 
	(
	select vscw.year, vscw.week, vscw.pcode, p.parent_id, vscw.distributor_id, coalesce(vscw.qty,0) as qty, coalesce(vscw.qty,0)*coalesce(mp.price,0) as salfo_value
	 from spx.v_salfo_confirm_weekly vscw inner join cycle_ranked cr on vscw.year = cr.year and vscw.week = cr.week left join spx.m_product p on vscw.pcode = p.pcode
		left join spx.m_distributor md on vscw.distributor_id = md.distributor_id  
		left join spx.m_price_divisi mp on vscw.year = mp.year and md.sls_div = mp.sls_div and vscw.pcode = mp.pcode
	) a
	group by year, week, parent_id, distributor_id
),
stock as (
	select a.year, a.period, a.week, a.distributor_id, a.parent_id, sum(qty) as stock_qty, sum(qty_value) as stock_value
	from 
	(
	select vss.year, vss.period, vss.week, vss.sub_id as distributor_id, vss.pcode, p.parent_id, vss.qty, (vss.qty * mp.price) as qty_value
	 from spx.v_stock_dist vss inner join cycle_ranked cr on vss.year = cr.year and vss.week = cr.week left join spx.m_product p on vss.pcode = p.pcode
			left join spx.m_distributor md on vss.sub_id = md.distributor_id  
			left join spx.m_price_divisi mp on vss.year = mp.year and md.sls_div = mp.sls_div and vss.pcode = mp.pcode
	) a	
	group by a.year, a.period, a.week, a.distributor_id, a.parent_id 
),
stm as (
select a.year, a.period, a.week, a.distributor_id, a.parent_id, sum(omsetqty) as stm_qty, sum(qty_value) as stm_value
	from 
	(
	select cast(vss.tahun as int) as year, vss.periode as period, cast(vss.week as int) as week, vss.distributor_id, vss.pcode, p.parent_id, vss.omsetqty, vss.omsetvalue as qty_value
	 from spx.v_omset_subdist_weekly_bw vss inner join cycle_ranked cr on cast(vss.tahun as int) = cr.year and cast(vss.week as int) = cr.week left join spx.m_product p on vss.pcode = p.pcode			
	) a	
	group by a.year, a.period, a.week, a.distributor_id, a.parent_id 
),
avgs as (
  select s.distributor_id, s.parent_id,
         sum(s.stm_qty)   filter (where w.in_5w)::numeric  / nullif((select count(*) from window_weeks where in_5w),  0) as avg_5w_qty,
         sum(s.stm_value) filter (where w.in_5w)::numeric  / nullif((select count(*) from window_weeks where in_5w),  0) as avg_5w_value,
         sum(s.stm_qty)   filter (where w.in_13w)::numeric / nullif((select count(*) from window_weeks where in_13w), 0) as avg_13w_qty,
         sum(s.stm_value) filter (where w.in_13w)::numeric / nullif((select count(*) from window_weeks where in_13w), 0) as avg_13w_value
  from stm s
  join window_weeks w
    on s.year = w.year and s.week = w.week
  where s.parent_id is not null
  group by s.distributor_id, s.parent_id
),
wh_stock as (
   select a.year, a.week, a.parent_id, SUM(a.qty) as stock_ibn, SUM(a.qty_value) as stock_ibn_value 
  from 
  (
  select a.year, a.week, a.pcode, mp.parent_id, mpd.price, a.qty, (a.qty * coalesce(mpd.price,0)) as qty_value
  from spx.t_stock_wh a inner join cycle_ranked cr on a.year = cr.year and a.week = cr.week  join spx.m_product mp on a.pcode = mp.pcode
     left join spx.m_price_divisi mpd on a.year = mpd.year and mp.sls_div = mpd.sls_div and a.pcode = mp.pcode
  ) a   
  group by a.year, a.week, a.parent_id
),
omset_ibn as (
  select a.year, a.week, mp.parent_id, distributor_id, sum(sta_qty) as sta_qty, sum(sta_value) as sta_value
  from spx.m_sta_subdist a inner join cycle_ranked cr on a.year = cr.year and a.week = cr.week 
  	join spx.m_product mp on a.pcode = mp.pcode
  group by a.year, a.week, mp.parent_id, distributor_id	
),
avgs_ibn as (
  select oi.parent_id, oi.distributor_id,
         avg(oi.sta_qty) filter (where w.in_5w) as avg_5w_sta_qty,
         avg(oi.sta_value) filter (where w.in_5w) as avg_5w_sta_value
  from omset_ibn oi
  join window_weeks w
    on oi.year = w.year and oi.week = w.week
  group by oi.parent_id, oi.distributor_id
),
fdos as
(
  SELECT a.year, a.period, a.week, a.distributor_id, a.parent_id, SUM(a.fdos_update) as fdos_update, SUM(a.fdos_value) as fdos_value
  FROM ( 
select vfu.year, vfu.period, vfu.week, vfu.distributor_id, mp.pcode, mp.parent_id, vfu.fdos_update, vfu.fdos_update * coalesce(mpd.price,0) as fdos_value 
   from spx.v_fdos_update vfu 
 	inner join cycle_ranked cw on vfu.year = cw.year and vfu.period = cw.period and vfu.week = cw.week
	inner join spx.m_product mp on vfu.pcode = mp.pcode
  inner join spx.m_distributor md on vfu.distributor_id = md.distributor_id
  left join spx.m_price_divisi mpd on vfu.pcode = mpd.pcode and vfu.year = mpd.year and md.sls_div = mpd.sls_div
 ) a
 GROUP BY a.year, a.period, a.week, a.distributor_id, a.parent_id
)
select md.sls_div as channel, voswb.year, cr.period, to_char(to_date(cast(cr.period as text), 'MM'), 'Mon') as periodName,voswb.week,
       vsh.nsm_id, vsh.nsm_name, vsh.grsm_id, vsh.grsm_name, vsh.rsm_id, vsh.rsm_name, vsh.ss_id, vsh.ss_name,
       mp.div_id as sbu_id, mdiv.div_nm as sbu_name, mp.brand_id, mbrand.brand_nm as brand_name, mp.subbrand_id, msubbrand.subbrand_nm as subbrand_name, 
       mp.parent_id, mparent.parent_nm as parent_name, mp.flag_season as flag_sku,
       voswb.distributor_id, md.distributor_nm as distributor_name, voswb.target_qty, voswb.target_value,
       round(coalesce(salfo.salfo_qty,0),2) as salfo_qty, round(coalesce(salfo.salfo_value,0),2) as salfo_value,
       stm.stm_qty, stm.stm_value,
       ws.stock_ibn, ws.stock_ibn_value, fdos.fdos_update, fdos.fdos_value, oi.sta_qty as sta_qty, oi.sta_value as sta_value,
       stock.stock_qty, stock.stock_value, a.avg_5w_qty,  a.avg_5w_value, a.avg_13w_qty, a.avg_13w_value, aibn.avg_5w_sta_qty, aibn.avg_5w_sta_value, now() as loaded_at, cr.flag
from (select distinct div_id, brand_id, subbrand_id, parent_id, flag_season from spx.m_product) mp
left join spx.m_division mdiv on mdiv.div_id = mp.div_id
left join spx.m_brand mbrand on mbrand.brand_id = mp.brand_id
left join spx.m_subbrand msubbrand
  on  msubbrand.subbrand_id = mp.subbrand_id
  and msubbrand.brand_id    = mp.brand_id
left join spx.m_parent mparent on mparent.parent_id = mp.parent_id
join spx.v_target_weekly_by_parent voswb on mp.parent_id = voswb.parent_id
join cycle_ranked cr on voswb.year = cr.year and voswb.week = cr.week
join spx.m_distributor md on voswb.distributor_id = md.distributor_id
left join sales_hierarchy vsh on voswb.distributor_id = vsh.distributor_id and voswb.parent_id = vsh.parent_id
left join stm on voswb.year = stm.year and voswb.week = stm.week and voswb.distributor_id = stm.distributor_id and voswb.parent_id = stm.parent_id
left join salfo on voswb.year = salfo.year and voswb.week = salfo.week and voswb.distributor_id = salfo.distributor_id and voswb.parent_id = salfo.parent_id
left join stock on voswb.year = stock.year and voswb.week = stock.week and voswb.distributor_id = stock.distributor_id and voswb.parent_id = stock.parent_id
left join fdos on voswb.year = fdos.year and voswb.week = fdos.week and voswb.distributor_id = fdos.distributor_id and voswb.parent_id = fdos.parent_id
left join wh_stock ws
  on voswb.year = ws.year and voswb.week = ws.week and voswb.parent_id = ws.parent_id
left join omset_ibn oi
  on voswb.year = oi.year and voswb.week = oi.week
  and voswb.parent_id = oi.parent_id and voswb.distributor_id = oi.distributor_id
left join avgs a
  on a.distributor_id = voswb.distributor_id and a.parent_id = voswb.parent_id
left join avgs_ibn aibn on voswb.parent_id = aibn.parent_id and voswb.distributor_id = aibn.distributor_id