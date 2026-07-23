{{ config(
    materialized='table',
    indexes=[
      {'columns': ['year', 'channel', 'period', 'week', 'parent_id', 'distributor_id']},
      {'columns': ['year','week','channel','sbu_name','grsm_name','rsm_name']}
      {'columns': ['year','period','channel','sbu_name']}      
      {'columns': ['year','week','distributor_id','parent_id']}
    ]
) }}

-- Grain: one row per (year, channel, period, week, product-group, distributor_id)
-- where product-group = (div_id, brand_id, subbrand_id, parent_id, flag_season).
--
-- Every metric is rolled up from pcode to that grain. Previously the model drove off
-- `select distinct div_id, brand_id, subbrand_id, parent_id, flag_season from m_product`
-- but joined metrics on parent_id alone, so a parent whose SKUs span >1 subbrand had its
-- single parent-level value COPIED onto each row instead of split -- inflating every sum
-- by the number of product groups under that parent (up to 5x; 123 of 1876 parents affected).

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
-- For every target week, list the source weeks feeding its rolling averages:
-- 5w window = rn-6..rn-2, 13w window = rn-14..rn-2 (current and previous week excluded).
week_windows as (
  select w.year, w.week,
         src.year as src_year, src.week as src_week,
         (src.rn between w.rn - 6  and w.rn - 2) as in_5w,
         (src.rn between w.rn - 14 and w.rn - 2) as in_13w
  from cycle_ranked w
  join cycle_ranked src on src.rn between w.rn - 14 and w.rn - 2
),
window_counts as (
  select year, week,
         count(*) filter (where in_5w)  as n_5w,
         count(*) filter (where in_13w) as n_13w
  from week_windows
  group by year, week
),

-- pcode -> its product group. pg_key is a NULL-safe surrogate for the 5-column group:
-- div_id/brand_id/subbrand_id/flag_season are nullable, and joining them with plain `=`
-- would silently drop those rows, while IS NOT DISTINCT FROM would block hash joins.
pcode_pg as (
  select distinct pcode, div_id, brand_id, subbrand_id, parent_id, flag_season,
         md5(coalesce(div_id::text,      '~') || '|' ||
             coalesce(brand_id::text,    '~') || '|' ||
             coalesce(subbrand_id::text, '~') || '|' ||
             parent_id::text                  || '|' ||
             coalesce(flag_season::text, '~')) as pg_key
  from spx.m_product
  where parent_id is not null
),
pg_dim as (
  select distinct pg_key, div_id, brand_id, subbrand_id, parent_id, flag_season
  from pcode_pg
),
-- One designated product group per parent. Targets are only available at parent grain
-- (v_target_weekly_by_parent has no pcode), so they attach here and are NULL elsewhere --
-- that keeps sum(target_qty) exact at parent level instead of multiplying it.
-- `nulls last` makes the pick deterministic across rebuilds.
pg_primary as (
  select parent_id, pg_key
  from (
    select parent_id, pg_key,
           row_number() over (
             partition by parent_id
             order by div_id nulls last, brand_id nulls last,
                      subbrand_id nulls last, flag_season nulls last
           ) as rn
    from pg_dim
  ) t
  where rn = 1
),
-- One hierarchy row per product group + distributor. 73 keys map to two salesmen for the
-- same pcode (Beverage, div_id 10); only ss_id ever differs -- nsm/grsm/rsm are identical
-- within every affected key -- so this picks a stable ss_id and no dimension above salesman
-- moves. Presentation collapse only: the underlying mapping in v_sales_hierarchy_product
-- is untouched.
sales_hierarchy as (
  select distinct on (pg.pg_key, v.distributor_id)
         pg.pg_key, v.distributor_id,
         v.nsm_id, v.nsm_name, v.grsm_id, v.grsm_name,
         v.rsm_id, v.rsm_name, v.ss_id, v.ss_name
  from spx.v_sales_hierarchy_product v
  join pcode_pg pg on v.pcode = pg.pcode
  order by pg.pg_key, v.distributor_id, v.ss_id nulls last
),

salfo as (
	select year, week, pg_key, distributor_id, sum(qty) as salfo_qty, sum(salfo_value) as salfo_value
	from
	(
	select vscw.year, vscw.week, vscw.pcode, pg.pg_key, vscw.distributor_id, coalesce(vscw.qty,0) as qty, coalesce(vscw.qty,0)*coalesce(mp.price,0) as salfo_value
	 from spx.v_salfo_confirm_weekly vscw inner join cycle_ranked cr on vscw.year = cr.year and vscw.week = cr.week join pcode_pg pg on vscw.pcode = pg.pcode
		left join spx.m_distributor md on vscw.distributor_id = md.distributor_id
		left join spx.m_price_divisi mp on vscw.year = mp.year and md.sls_div = mp.sls_div and vscw.pcode = mp.pcode
	) a
	group by year, week, pg_key, distributor_id
),
stock as (
	select a.year, a.week, a.distributor_id, a.pg_key, sum(qty) as stock_qty, sum(qty_value) as stock_value
	from
	(
	select vss.year, vss.week, vss.sub_id as distributor_id, vss.pcode, pg.pg_key, vss.qty, (vss.qty * mp.price) as qty_value
	 from spx.v_stock_dist vss inner join cycle_ranked cr on vss.year = cr.year and vss.week = cr.week join pcode_pg pg on vss.pcode = pg.pcode
			left join spx.m_distributor md on vss.sub_id = md.distributor_id
			left join spx.m_price_divisi mp on vss.year = mp.year and md.sls_div = mp.sls_div and vss.pcode = mp.pcode
	) a
	group by a.year, a.week, a.distributor_id, a.pg_key
),
stm as (
select a.year, a.week, a.distributor_id, a.pg_key, sum(omsetqty) as stm_qty, sum(qty_value) as stm_value
	from
	(
	select cast(vss.tahun as int) as year, cast(vss.week as int) as week, vss.distributor_id, vss.pcode, pg.pg_key, vss.omsetqty, vss.omsetvalue as qty_value
	 from spx.v_omset_subdist_weekly_bw vss inner join cycle_ranked cr on cast(vss.tahun as int) = cr.year and cast(vss.week as int) = cr.week join pcode_pg pg on vss.pcode = pg.pcode
	) a
	group by a.year, a.week, a.distributor_id, a.pg_key
),
avgs as (
  select ww.year, ww.week, s.distributor_id, s.pg_key,
         sum(s.stm_qty)   filter (where ww.in_5w)::numeric  / nullif(wc.n_5w,  0) as avg_5w_qty,
         sum(s.stm_value) filter (where ww.in_5w)::numeric  / nullif(wc.n_5w,  0) as avg_5w_value,
         sum(s.stm_qty)   filter (where ww.in_13w)::numeric / nullif(wc.n_13w, 0) as avg_13w_qty,
         sum(s.stm_value) filter (where ww.in_13w)::numeric / nullif(wc.n_13w, 0) as avg_13w_value
  from week_windows ww
  join window_counts wc on wc.year = ww.year and wc.week = ww.week
  join stm s on s.year = ww.src_year and s.week = ww.src_week
  group by ww.year, ww.week, s.distributor_id, s.pg_key, wc.n_5w, wc.n_13w
),
-- Unchanged: keyed on parent_id with no distributor, so stock_ibn is still replicated
-- across distributors and product groups (pre-existing; out of scope -- never SUM it
-- across distributors). The m_price_divisi join below is also mis-keyed on `mp.pcode`
-- (m_product) instead of `mpd.pcode` -- deferred, tracked separately.
wh_stock as (
   select a.year, a.week, a.parent_id, SUM(a.qty) as stock_ibn, SUM(a.qty_value) as stock_ibn_value
  from
  (
  select a.year, a.week, a.pcode, mp.parent_id, mpd.price, a.qty+a.git_qty as qty, ((a.qty+a.git_qty) * coalesce(mpd.price,0)) as qty_value
  from spx.t_stock_wh_fdisupd a inner join cycle_ranked cr on a.year = cr.year and a.week = cr.week  join spx.m_product mp on a.pcode = mp.pcode
     left join spx.m_price_divisi mpd on a.year = mpd.year and mp.sls_div = mpd.sls_div and a.pcode = mp.pcode
  ) a
  group by a.year, a.week, a.parent_id
),
omset_ibn as (
  select a.year, a.week, pg.pg_key, distributor_id, sum(sta_qty) as sta_qty, sum(sta_value) as sta_value
  from spx.m_sta_subdist a inner join cycle_ranked cr on a.year = cr.year and a.week = cr.week
  	join pcode_pg pg on a.pcode = pg.pcode
  group by a.year, a.week, pg.pg_key, distributor_id
),
avgs_ibn as (
  select ww.year, ww.week, oi.pg_key, oi.distributor_id,
         avg(oi.sta_qty)   filter (where ww.in_5w) as avg_5w_sta_qty,
         avg(oi.sta_value) filter (where ww.in_5w) as avg_5w_sta_value
  from week_windows ww
  join omset_ibn oi on oi.year = ww.src_year and oi.week = ww.src_week
  group by ww.year, ww.week, oi.pg_key, oi.distributor_id
),
fdos as
(
  SELECT a.year, a.week, a.distributor_id, a.pg_key, SUM(a.fdos_update) as fdos_update, SUM(a.fdos_value) as fdos_value
  FROM (
select vfu.year, vfu.week, vfu.distributor_id, pg.pcode, pg.pg_key, vfu.fdos_update, vfu.fdos_update * coalesce(mpd.price,0) as fdos_value
   from spx.v_fdos_update vfu
 	inner join cycle_ranked cw on vfu.year = cw.year and vfu.period = cw.period and vfu.week = cw.week
	inner join pcode_pg pg on vfu.pcode = pg.pcode
  inner join spx.m_distributor md on vfu.distributor_id = md.distributor_id
  left join spx.m_price_divisi mpd on vfu.pcode = mpd.pcode and vfu.year = mpd.year and md.sls_div = mpd.sls_div
 ) a
 GROUP BY a.year, a.week, a.distributor_id, a.pg_key
),
-- Parent-grain target pinned onto the designated product group.
target as (
  select v.year, v.week, v.distributor_id, p.pg_key, v.target_qty, v.target_value
  from spx.v_target_weekly_by_parent v
  join pg_primary p on p.parent_id = v.parent_id
),
-- Every key present in any source. Replaces the old target-driven select + `extra_keys`
-- mirror, which duplicated ~75 lines of SELECT and could drift apart. `union` dedupes,
-- so a key found in several sources still yields one row. fdos is deliberately excluded,
-- matching the previous extra_keys behaviour.
all_keys as (
  select year, week, pg_key, distributor_id from stm
  union
  select year, week, pg_key, distributor_id from salfo
  union
  select year, week, pg_key, distributor_id from stock
  union
  select year, week, pg_key, distributor_id from omset_ibn
  union
  select year, week, pg_key, distributor_id from target
)

select md.sls_div as channel, k.year, cr.period, to_char(to_date(cast(cr.period as text), 'MM'), 'Mon') as periodName, k.week,
       vsh.nsm_id, vsh.nsm_name, vsh.grsm_id, vsh.grsm_name, vsh.rsm_id, vsh.rsm_name, vsh.ss_id, vsh.ss_name,
       d.div_id as sbu_id, mdiv.div_nm as sbu_name, d.brand_id, mbrand.brand_nm as brand_name, d.subbrand_id, msubbrand.subbrand_nm as subbrand_name,
       d.parent_id, mparent.parent_nm as parent_name, d.flag_season as flag_sku,
       k.distributor_id, md.distributor_nm as distributor_name, t.target_qty, t.target_value,
       round(coalesce(salfo.salfo_qty,0),2) as salfo_qty, round(coalesce(salfo.salfo_value,0),2) as salfo_value,
       stm.stm_qty, stm.stm_value,
       ws.stock_ibn, ws.stock_ibn_value, fdos.fdos_update, fdos.fdos_value, oi.sta_qty as sta_qty, oi.sta_value as sta_value,
       stock.stock_qty, stock.stock_value, a.avg_5w_qty,  a.avg_5w_value, a.avg_13w_qty, a.avg_13w_value, aibn.avg_5w_sta_qty, aibn.avg_5w_sta_value, now() as loaded_at, cr.flag
from all_keys k
join cycle_ranked cr on cr.year = k.year and cr.week = k.week
join pg_dim d on d.pg_key = k.pg_key
join spx.m_distributor md on md.distributor_id = k.distributor_id
left join spx.m_division mdiv on mdiv.div_id = d.div_id
left join spx.m_brand mbrand on mbrand.brand_id = d.brand_id
-- subbrand_id is not globally unique (603 exists under brand 601 GENTLEGEN PCH and
-- brand 602 HAND SOAP), so both keys are required here.
left join spx.m_subbrand msubbrand
  on  msubbrand.subbrand_id = d.subbrand_id
  and msubbrand.brand_id    = d.brand_id
left join spx.m_parent mparent on mparent.parent_id = d.parent_id
left join sales_hierarchy vsh on vsh.pg_key = k.pg_key and vsh.distributor_id = k.distributor_id
left join target t
  on t.year = k.year and t.week = k.week and t.pg_key = k.pg_key and t.distributor_id = k.distributor_id
left join stm
  on stm.year = k.year and stm.week = k.week and stm.pg_key = k.pg_key and stm.distributor_id = k.distributor_id
left join salfo
  on salfo.year = k.year and salfo.week = k.week and salfo.pg_key = k.pg_key and salfo.distributor_id = k.distributor_id
left join stock
  on stock.year = k.year and stock.week = k.week and stock.pg_key = k.pg_key and stock.distributor_id = k.distributor_id
left join fdos
  on fdos.year = k.year and fdos.week = k.week and fdos.pg_key = k.pg_key and fdos.distributor_id = k.distributor_id
left join omset_ibn oi
  on oi.year = k.year and oi.week = k.week and oi.pg_key = k.pg_key and oi.distributor_id = k.distributor_id
left join wh_stock ws
  on ws.year = k.year and ws.week = k.week and ws.parent_id = d.parent_id
left join avgs a
  on a.year = k.year and a.week = k.week and a.pg_key = k.pg_key and a.distributor_id = k.distributor_id
left join avgs_ibn aibn
  on aibn.year = k.year and aibn.week = k.week and aibn.pg_key = k.pg_key and aibn.distributor_id = k.distributor_id
