{{ config(
    materialized='table',
    pre_hook="set local work_mem = '256MB'",
    indexes=[
      {'columns': ['year', 'channel', 'period', 'week', 'parent_id', 'distributor_id']},
      {'columns': ['year','week','channel','sbu_name','grsm_name','rsm_name']},
      {'columns': ['year','period','channel','sbu_name']},
      {'columns': ['year','week','distributor_id','parent_id']},
      {'columns': ['year','channel','period','week','distributor_id','pg_id']}
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

-- Product-group dimension with a dense integer surrogate. pg_id (4 bytes) is what every
-- downstream CTE groups and joins on, instead of the 5 attribute columns:
--   * div_id/brand_id/subbrand_id/flag_season are nullable, so plain `=` would silently
--     drop those rows, and IS NOT DISTINCT FROM cannot be used as a hash key at all;
--   * a text/md5 surrogate is NULL-safe but widens every hash and sort key across 6
--     aggregations, a UNION dedup and 9 joins over millions of rows -- enough to spill
--     work_mem to disk everywhere.
-- The NULL-safe comparison is therefore paid exactly once, against ~2k product groups.
pg_dim as (
  select row_number() over (
           order by parent_id, div_id nulls last, brand_id nulls last,
                    subbrand_id nulls last, flag_season nulls last
         )::int as pg_id,
         div_id, brand_id, subbrand_id, parent_id, flag_season
  from (select distinct div_id, brand_id, subbrand_id, parent_id, flag_season
        from spx.m_product where parent_id is not null) g
),
pcode_pg as (
  select p.pcode, d.pg_id
  from (select distinct pcode, div_id, brand_id, subbrand_id, parent_id, flag_season
        from spx.m_product where parent_id is not null) p
  join pg_dim d
    on  d.parent_id   = p.parent_id
    and d.div_id      is not distinct from p.div_id
    and d.brand_id    is not distinct from p.brand_id
    and d.subbrand_id is not distinct from p.subbrand_id
    and d.flag_season is not distinct from p.flag_season
),
-- One designated product group per parent. Targets are only available at parent grain
-- (v_target_weekly_by_parent has no pcode), so they attach here and are NULL elsewhere --
-- that keeps sum(target_qty) exact at parent level instead of multiplying it.
-- pg_dim's row_number is ordered parent-first, so min(pg_id) is a deterministic pick.
pg_primary as (
  select parent_id, min(pg_id) as pg_id
  from pg_dim
  group by parent_id
),
-- One hierarchy row per product group + distributor. 73 keys map to two salesmen for the
-- same pcode (Beverage, div_id 10); only ss_id ever differs -- nsm/grsm/rsm are identical
-- within every affected key -- so this picks a stable ss_id and no dimension above salesman
-- moves. Presentation collapse only: the underlying mapping in v_sales_hierarchy_product
-- is untouched.
-- The inner `distinct` collapses pcode-level duplicates with a hash aggregate first, so the
-- DISTINCT ON only has to sort one row per (product group, distributor, hierarchy).
sales_hierarchy as (
  select distinct on (pg_id, distributor_id)
         pg_id, distributor_id,
         nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name, ss_id, ss_name
  from (
    select distinct pc.pg_id, v.distributor_id,
           v.nsm_id, v.nsm_name, v.grsm_id, v.grsm_name,
           v.rsm_id, v.rsm_name, v.ss_id, v.ss_name
    from spx.v_sales_hierarchy_product v
    join pcode_pg pc on v.pcode = pc.pcode
  ) t
  order by pg_id, distributor_id, ss_id nulls last
),

salfo as (
	select year, week, pg_id, distributor_id, sum(qty) as salfo_qty, sum(salfo_value) as salfo_value
	from
	(
	select vscw.year, vscw.week, vscw.pcode, pg.pg_id, vscw.distributor_id, coalesce(vscw.qty,0) as qty, coalesce(vscw.qty,0)*coalesce(mp.price,0) as salfo_value
	 from spx.v_salfo_confirm_weekly vscw inner join cycle_ranked cr on vscw.year = cr.year and vscw.week = cr.week join pcode_pg pg on vscw.pcode = pg.pcode
		left join spx.m_distributor md on vscw.distributor_id = md.distributor_id
		left join spx.m_price_divisi mp on vscw.year = mp.year and md.sls_div = mp.sls_div and vscw.pcode = mp.pcode
	) a
	group by year, week, pg_id, distributor_id
),
stock as (
	select a.year, a.week, a.distributor_id, a.pg_id, sum(qty) as stock_qty, sum(qty_value) as stock_value
	from
	(
	select vss.year, vss.week, vss.sub_id as distributor_id, vss.pcode, pg.pg_id, vss.qty, (vss.qty * mp.price) as qty_value
	 from spx.v_stock_dist vss inner join cycle_ranked cr on vss.year = cr.year and vss.week = cr.week join pcode_pg pg on vss.pcode = pg.pcode
			left join spx.m_distributor md on vss.sub_id = md.distributor_id
			left join spx.m_price_divisi mp on vss.year = mp.year and md.sls_div = mp.sls_div and vss.pcode = mp.pcode
	) a
	group by a.year, a.week, a.distributor_id, a.pg_id
),
stm as (
select a.year, a.week, a.distributor_id, a.pg_id, sum(omsetqty) as stm_qty, sum(qty_value) as stm_value
	from
	(
	select cast(vss.tahun as int) as year, cast(vss.week as int) as week, vss.distributor_id, vss.pcode, pg.pg_id, vss.omsetqty, vss.omsetvalue as qty_value
	 from spx.v_omset_subdist_weekly_bw vss inner join cycle_ranked cr on cast(vss.tahun as int) = cr.year and cast(vss.week as int) = cr.week join pcode_pg pg on vss.pcode = pg.pcode
	) a
	group by a.year, a.week, a.distributor_id, a.pg_id
),
-- n_5w/n_13w are functionally dependent on (year, week), so they are joined AFTER the
-- aggregate rather than widening its grouping key. Same arithmetic: the ::numeric cast
-- still lands on the sum, before the division.
avgs as (
  select s.year, s.week, s.distributor_id, s.pg_id,
         s.s5_qty  / nullif(wc.n_5w,  0) as avg_5w_qty,
         s.s5_val  / nullif(wc.n_5w,  0) as avg_5w_value,
         s.s13_qty / nullif(wc.n_13w, 0) as avg_13w_qty,
         s.s13_val / nullif(wc.n_13w, 0) as avg_13w_value
  from (
    select ww.year, ww.week, s.distributor_id, s.pg_id,
           sum(s.stm_qty)   filter (where ww.in_5w)::numeric  as s5_qty,
           sum(s.stm_value) filter (where ww.in_5w)::numeric  as s5_val,
           sum(s.stm_qty)   filter (where ww.in_13w)::numeric as s13_qty,
           sum(s.stm_value) filter (where ww.in_13w)::numeric as s13_val
    from week_windows ww
    join stm s on s.year = ww.src_year and s.week = ww.src_week
    group by ww.year, ww.week, s.distributor_id, s.pg_id
  ) s
  join window_counts wc on wc.year = s.year and wc.week = s.week
),
-- Still keyed on parent_id with no distributor, so stock_ibn is replicated across
-- distributors and product groups (pre-existing; out of scope -- never SUM it across
-- distributors).
wh_stock as (
   select a.year, a.week, a.parent_id, SUM(a.qty) as stock_ibn, SUM(a.qty_value) as stock_ibn_value
  from
  (
  select a.year, a.week, a.pcode, mp.parent_id, mpd.price, a.qty+a.git_qty as qty, ((a.qty+a.git_qty) * coalesce(mpd.price,0)) as qty_value
  from spx.t_stock_wh_fdisupd a inner join cycle_ranked cr on a.year = cr.year and a.week = cr.week  join spx.m_product mp on a.pcode = mp.pcode
     left join spx.m_price_divisi mpd on a.year = mpd.year and mp.sls_div = mpd.sls_div and a.pcode = mpd.pcode
  ) a
  group by a.year, a.week, a.parent_id
),
omset_ibn as (
  select a.year, a.week, pg.pg_id, distributor_id, sum(sta_qty) as sta_qty, sum(sta_value) as sta_value
  from spx.m_sta_subdist a inner join cycle_ranked cr on a.year = cr.year and a.week = cr.week
  	join pcode_pg pg on a.pcode = pg.pcode
  group by a.year, a.week, pg.pg_id, distributor_id
),
avgs_ibn as (
  select ww.year, ww.week, oi.pg_id, oi.distributor_id,
         avg(oi.sta_qty)   filter (where ww.in_5w) as avg_5w_sta_qty,
         avg(oi.sta_value) filter (where ww.in_5w) as avg_5w_sta_value
  from week_windows ww
  join omset_ibn oi on oi.year = ww.src_year and oi.week = ww.src_week
  group by ww.year, ww.week, oi.pg_id, oi.distributor_id
),
fdos as
(
  SELECT a.year, a.week, a.distributor_id, a.pg_id, SUM(a.fdos_update) as fdos_update, SUM(a.fdos_value) as fdos_value
  FROM (
select vfu.year, vfu.week, vfu.distributor_id, pg.pcode, pg.pg_id, vfu.fdos_update, vfu.fdos_update * coalesce(mpd.price,0) as fdos_value
   from spx.v_fdos_update vfu
 	inner join cycle_ranked cw on vfu.year = cw.year and vfu.period = cw.period and vfu.week = cw.week
	inner join pcode_pg pg on vfu.pcode = pg.pcode
  inner join spx.m_distributor md on vfu.distributor_id = md.distributor_id
  left join spx.m_price_divisi mpd on vfu.pcode = mpd.pcode and vfu.year = mpd.year and md.sls_div = mpd.sls_div
 ) a
 GROUP BY a.year, a.week, a.distributor_id, a.pg_id
),
-- Parent-grain target pinned onto the designated product group.
target as (
  select v.year, v.week, v.distributor_id, p.pg_id, v.target_qty, v.target_value
  from spx.v_target_weekly_by_parent v
  join pg_primary p on p.parent_id = v.parent_id
),
-- Every key present in any source. Replaces the old target-driven select + `extra_keys`
-- mirror, which duplicated ~75 lines of SELECT and could drift apart. `union` dedupes,
-- so a key found in several sources still yields one row. fdos is deliberately excluded,
-- matching the previous extra_keys behaviour.
all_keys as (
  select year, week, pg_id, distributor_id from stm
  union
  select year, week, pg_id, distributor_id from salfo
  union
  select year, week, pg_id, distributor_id from stock
  union
  select year, week, pg_id, distributor_id from omset_ibn
  union
  select year, week, pg_id, distributor_id from target
)

select md.sls_div as channel, k.year, cr.period, to_char(to_date(cast(cr.period as text), 'MM'), 'Mon') as periodName, k.week,
       vsh.nsm_id, vsh.nsm_name, vsh.grsm_id, vsh.grsm_name, vsh.rsm_id, vsh.rsm_name, vsh.ss_id, vsh.ss_name,
       d.div_id as sbu_id, mdiv.div_nm as sbu_name, d.brand_id, mbrand.brand_nm as brand_name, d.subbrand_id, msubbrand.subbrand_nm as subbrand_name,
       d.parent_id, mparent.parent_nm as parent_name, d.flag_season as flag_sku,
       k.distributor_id, md.distributor_nm as distributor_name, t.target_qty, t.target_value,
       round(coalesce(salfo.salfo_qty,0),2) as salfo_qty, round(coalesce(salfo.salfo_value,0),2) as salfo_value,
       stm.stm_qty, stm.stm_value,
       ws.stock_ibn, ws.stock_ibn_value, fdos.fdos_update, fdos.fdos_value, oi.sta_qty as sta_qty, oi.sta_value as sta_value,
       stock.stock_qty, stock.stock_value, a.avg_5w_qty,  a.avg_5w_value, a.avg_13w_qty, a.avg_13w_value, aibn.avg_5w_sta_qty, aibn.avg_5w_sta_value, now() as loaded_at, cr.flag,
       -- appended last so every existing column position stays stable for Superset.
       -- silver_sales_performance_chart joins prior year on this instead of the five
       -- product-attribute columns: one integer equality, hash-joinable and NULL-free.
       k.pg_id
from all_keys k
join cycle_ranked cr on cr.year = k.year and cr.week = k.week
join pg_dim d on d.pg_id = k.pg_id
join spx.m_distributor md on md.distributor_id = k.distributor_id
left join spx.m_division mdiv on mdiv.div_id = d.div_id
left join spx.m_brand mbrand on mbrand.brand_id = d.brand_id
-- subbrand_id is not globally unique (603 exists under brand 601 GENTLEGEN PCH and
-- brand 602 HAND SOAP), so both keys are required here.
left join spx.m_subbrand msubbrand
  on  msubbrand.subbrand_id = d.subbrand_id
  and msubbrand.brand_id    = d.brand_id
left join spx.m_parent mparent on mparent.parent_id = d.parent_id
left join sales_hierarchy vsh on vsh.pg_id = k.pg_id and vsh.distributor_id = k.distributor_id
left join target t
  on t.year = k.year and t.week = k.week and t.pg_id = k.pg_id and t.distributor_id = k.distributor_id
left join stm
  on stm.year = k.year and stm.week = k.week and stm.pg_id = k.pg_id and stm.distributor_id = k.distributor_id
left join salfo
  on salfo.year = k.year and salfo.week = k.week and salfo.pg_id = k.pg_id and salfo.distributor_id = k.distributor_id
left join stock
  on stock.year = k.year and stock.week = k.week and stock.pg_id = k.pg_id and stock.distributor_id = k.distributor_id
left join fdos
  on fdos.year = k.year and fdos.week = k.week and fdos.pg_id = k.pg_id and fdos.distributor_id = k.distributor_id
left join omset_ibn oi
  on oi.year = k.year and oi.week = k.week and oi.pg_id = k.pg_id and oi.distributor_id = k.distributor_id
left join wh_stock ws
  on ws.year = k.year and ws.week = k.week and ws.parent_id = d.parent_id
left join avgs a
  on a.year = k.year and a.week = k.week and a.pg_id = k.pg_id and a.distributor_id = k.distributor_id
left join avgs_ibn aibn
  on aibn.year = k.year and aibn.week = k.week and aibn.pg_id = k.pg_id and aibn.distributor_id = k.distributor_id
