{{ config(materialized='table') }}

with cycle_ranked as (
  select year, week,
         min(cdate) as week_start,
         max(cdate) as week_end,
         row_number() over (order by min(cdate)) as rn
  from spx.m_cycle3
  group by year, week
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
avgs as (
  select v.distributor_id, v.pcode,
         sum(v.omsetqty)   filter (where w.in_5w)::numeric  / nullif((select count(*) from window_weeks where in_5w),  0) as avg_5w_qty,
         sum(v.omsetvalue) filter (where w.in_5w)::numeric  / nullif((select count(*) from window_weeks where in_5w),  0) as avg_5w_value,
         sum(v.omsetqty)   filter (where w.in_13w)::numeric / nullif((select count(*) from window_weeks where in_13w), 0) as avg_13w_qty,
         sum(v.omsetvalue) filter (where w.in_13w)::numeric / nullif((select count(*) from window_weeks where in_13w), 0) as avg_13w_value
  from spx.v_omset_subdist_weekly_bw v
  join window_weeks w
    on cast(v.tahun as int) = w.year and cast(v.week as int) = w.week
  group by v.distributor_id, v.pcode
),
wh_stock as (
  select year, week, pcode, sum(qty) as stock_ibn
  from spx.t_stock_wh
  group by year, week, pcode
),
omset_ibn as (
  select year, week, pcode, sum(qty_omset) as omset
  from spx.t_omset
  group by year, week, pcode
),
avgs_ibn as (
  select oi.pcode,
         avg(oi.omset) filter (where w.in_5w) as avg_5w_sta_qty
  from omset_ibn oi
  join window_weeks w
    on oi.year = w.year and oi.week = w.week
  group by oi.pcode
)
select md.sls_div as channel, voswb.tahun as year, voswb.periode as period, to_char(to_date(cast(voswb.periode as text), 'MM'), 'Mon') as periodName, voswb.week,
       vsh.nsm_id, vsh.nsm_name, vsh.grsm_id, vsh.grsm_name, vsh.rsm_id, vsh.rsm_name, vsh.ss_id, vsh.ss_name,
       mp.div_id as sbu_id, mdiv.div_nm as sbu_name, mp.brand_id, mbrand.brand_nm as brand_name, mp.subbrand_id, msubbrand.subbrand_nm as subbrand_name, mp.parent_id, mparent.parent_nm as parent_name,
       mp.pcode, mp.pcodename, mp.flag_season as flag_sku,
       voswb.distributor_id, md.distributor_nm as distributorN_name, voswb.omsetqty as stm_qty, voswb.omsetvalue as stm_value,
       vscw.qty as salfo_qty, vscw.qty * coalesce(mpd.price,0) as salfo_value,
       ttw.target_qty, ttw.target_value, sss.qty as stock_subdist,
       ws.stock_ibn, oi.omset as sta,
       a.avg_5w_qty,  a.avg_5w_value,
       a.avg_13w_qty, a.avg_13w_value, aibn.avg_5w_sta_qty, now() as loaded_at
from spx.m_product mp
left join spx.m_division mdiv on mdiv.div_id = mp.div_id
left join spx.m_brand mbrand on mbrand.brand_id = mp.brand_id
left join spx.m_subbrand msubbrand
  on  msubbrand.subbrand_id = mp.subbrand_id
  and msubbrand.brand_id    = mp.brand_id
left join spx.m_parent mparent on mparent.parent_id = mp.parent_id
join spx.v_omset_subdist_weekly_bw voswb on mp.pcode = voswb.pcode
join spx.m_distributor md on voswb.distributor_id = md.distributor_id
join spx.v_sales_hierarchy vsh on voswb.distributor_id = vsh.distributor_id
join spx.m_emp_team met on met.distributor_id = voswb.distributor_id and met.emp_id = vsh.ss_id
join spx.m_team tm ON met.team_id = tm.team_id and mp.div_id = tm.div_id
left join spx.v_salfo_confirm_weekly vscw on cast(voswb.tahun as int) =vscw.year and cast(voswb.week as int) = vscw.week and voswb.pcode = vscw.pcode and voswb.distributor_id = vscw.distributor_id
left join spx.t_target_weekly ttw
  on cast(voswb.tahun as int) = ttw.year and cast(voswb.week as int) = ttw.week
  and voswb.pcode = ttw.pcode and voswb.distributor_id = ttw.distributor_id
left join spx.silver_stock_subdist sss
  on cast(voswb.tahun as int) = sss.year and cast(voswb.week as int) = sss.week
  and voswb.pcode = sss.pcode and voswb.distributor_id = sss.distributor_id
left join wh_stock ws
  on cast(voswb.tahun as int) = ws.year and cast(voswb.week as int) = ws.week
  and voswb.pcode = ws.pcode
left join omset_ibn oi
  on cast(voswb.tahun as int) = oi.year and cast(voswb.week as int) = oi.week
  and voswb.pcode = oi.pcode
left join avgs a
  on a.distributor_id = voswb.distributor_id and a.pcode = voswb.pcode
left join avgs_ibn aibn on voswb.pcode = aibn.pcode
left join spx.m_price_divisi mpd on cast(voswb.tahun as int) =mpd.year and voswb.pcode = mpd.pcode and md.sls_div = mpd.sls_div