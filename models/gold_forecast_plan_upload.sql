{{ config(
    materialized='table',
    pre_hook=[
      "set local work_mem = '256MB'",
      "drop table if exists tmp_pg_dim",
      "create temp table tmp_pg_dim as
         select row_number() over (
                  order by parent_id, div_id nulls last, brand_id nulls last,
                           subbrand_id nulls last, flag_season nulls last
                )::int as pg_id,
                div_id, brand_id, subbrand_id, parent_id, flag_season
         from (select distinct div_id, brand_id, subbrand_id, parent_id, flag_season
               from spx.m_product where parent_id is not null) g",
      "create unique index on tmp_pg_dim (pg_id)",
      "create index on tmp_pg_dim (parent_id)",
      "analyze tmp_pg_dim",
      "drop table if exists tmp_pcode_pg",
      "create temp table tmp_pcode_pg as
         select p.pcode, d.pg_id
         from (select distinct pcode, div_id, brand_id, subbrand_id, parent_id, flag_season
               from spx.m_product where parent_id is not null) p
         join tmp_pg_dim d
           on  d.parent_id   = p.parent_id
           and d.div_id      is not distinct from p.div_id
           and d.brand_id    is not distinct from p.brand_id
           and d.subbrand_id is not distinct from p.subbrand_id
           and d.flag_season is not distinct from p.flag_season",
      "create index on tmp_pcode_pg (pcode)",
      "create index on tmp_pcode_pg (pg_id)",
      "analyze tmp_pcode_pg"
    ],
    indexes=[
      {'columns': ['year_upload', 'period_upload', 'year', 'period']},
      {'columns': ['year', 'period', 'channel', 'parent_id']},
      {'columns': ['distributor_id', 'parent_id']},
      {'columns': ['pg_id']},
      {'columns': ['lead_months']}
    ]
) }}

-- Forecast/plan uploads, keyed on BOTH the upload month and the month being forecast.
--
-- Every other model in this project reads the flattened weekly views (v_fdos_update,
-- v_fdis_update, t_salfo_confirm_weekly), which have already collapsed the upload
-- dimension away. The header tables keep it: (year_upload, period_upload) is when the
-- number was submitted, (year, period) is the month it forecasts. One upload covers
-- several future months -- a February upload carries March, April and May -- so this is
-- the only place forecast-vintage analysis (M+1 vs M+2 vs M+3) is possible.
--
-- Grain, MIXED BY DESIGN:
--   * fdos_plan / salfo rows: (year_upload, period_upload, year, period, channel, pg_id,
--     distributor_id) -- full sales hierarchy attached.
--   * fdis_plan rows:         (year_upload, period_upload, year, period, channel, pg_id)
--     with distributor_id NULL.
-- t_fdis_plan_h / t_fdis_marketing_h have no sub_id, and nothing in spx maps their
-- wh_id/buyer_id/plant_id to a distributor_id (m_distributor carries none of those
-- columns), so FDIS cannot be attributed below channel. Consequences:
--   * a filter on distributor_id / ss_id / rsm_id / grsm_id / nsm_id silently drops
--     EVERY fdis_plan row;
--   * each metric is safe to SUM on its own, but the three are only comparable when
--     sliced at product x channel x period.
--
-- There is no `week` column: all four sources are monthly uploads with no week key.
--
-- pg_id is the same product-group surrogate as silver_sales_performance_parent (same
-- row_number ordering over the same m_product rows), so the two models join on it.
-- Metrics roll pcode -> pg_id rather than pcode -> parent_id: joining on parent_id alone
-- copies a parent-level value onto each of its product groups instead of splitting it.

with pg_dim as not materialized (
  select pg_id, div_id, brand_id, subbrand_id, parent_id, flag_season
  from tmp_pg_dim
),
pcode_pg as not materialized (
  select pcode, pg_id
  from tmp_pcode_pg
),
-- One hierarchy row per product group + distributor. 73 keys map to two salesmen for the
-- same pcode (Beverage, div_id 10); only ss_id ever differs, so this picks a stable ss_id
-- and no dimension above salesman moves.
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

-- sub_id is the distributor key in the logistic header tables, the same way v_stock_dist
-- exposes it. m_distributor is joined INNER so channel is never NULL, matching
-- silver_sales_performance_parent.
fdos as (
  select f.year_upload, f.period_upload, f.year, f.period,
         md.sls_div as channel, pg.pg_id, f.sub_id as distributor_id,
         sum(coalesce(f.qty, 0)) as fdos_plan
  from spx.t_fdos_h f
  join pcode_pg pg on pg.pcode = f.pcode
  join spx.m_distributor md on md.distributor_id = f.sub_id
  where f.year_upload >= extract(year from current_date) - 1
  group by f.year_upload, f.period_upload, f.year, f.period, md.sls_div, pg.pg_id, f.sub_id
),

-- Marketing's number overrides the uploaded plan where it exists, but the two tables do
-- not cover the same key set in either direction -- hence FULL OUTER on their shared
-- 10-column primary key, and coalesce on every key column as well as on the qty.
fdis as (
  select k.year_upload, k.period_upload, k.year, k.period,
         k.channel, pg.pg_id, null::varchar as distributor_id,
         sum(coalesce(k.qty, 0)) as fdis_plan
  from (
    select coalesce(m.year_upload,   p.year_upload)   as year_upload,
           coalesce(m.period_upload, p.period_upload) as period_upload,
           coalesce(m.year,          p.year)          as year,
           coalesce(m.period,        p.period)        as period,
           coalesce(m.sls_div,       p.sls_div)       as channel,
           coalesce(m.pcode,         p.pcode)         as pcode,
           coalesce(m.qty_final,     p.qty)           as qty
    from spx.t_fdis_marketing_h m
    full outer join spx.t_fdis_plan_h p
      on  p.year_upload   = m.year_upload
      and p.period_upload = m.period_upload
      and p.year          = m.year
      and p.period        = m.period
      and p.wh_id         = m.wh_id
      and p.buyer_id      = m.buyer_id
      and p.plant_id      = m.plant_id
      and p.ct_id         = m.ct_id
      and p.pcode         = m.pcode
      and p.sls_div       = m.sls_div
    where coalesce(m.year_upload, p.year_upload) >= extract(year from current_date) - 1
  ) k
  join pcode_pg pg on pg.pcode = k.pcode
  group by k.year_upload, k.period_upload, k.year, k.period, k.channel, pg.pg_id
),

salfo as (
  select s.year_upload, s.period_upload, s.year, s.period,
         md.sls_div as channel, pg.pg_id, s.sub_id as distributor_id,
         sum(coalesce(s.qty, 0)) as salfo
  from spx.t_salfo_confirm_h s
  join pcode_pg pg on pg.pcode = s.pcode
  join spx.m_distributor md on md.distributor_id = s.sub_id
  where s.year_upload >= extract(year from current_date) - 1
  group by s.year_upload, s.period_upload, s.year, s.period, md.sls_div, pg.pg_id, s.sub_id
),

-- Stacked long-form rather than a `union` key spine + three left joins: distributor_id is
-- NULL on every fdis row, so joining on it would need `is not distinct from` and lose the
-- hash joins. `group by` puts the NULL distributor in its own group, which is exactly the
-- separation we want.
metrics as (
  select year_upload, period_upload, year, period, channel, pg_id, distributor_id,
         fdos_plan, 0 as fdis_plan, 0 as salfo
  from fdos
  union all
  select year_upload, period_upload, year, period, channel, pg_id, distributor_id,
         0, fdis_plan, 0
  from fdis
  union all
  select year_upload, period_upload, year, period, channel, pg_id, distributor_id,
         0, 0, salfo
  from salfo
),
agg as (
  select year_upload, period_upload, year, period, channel, pg_id, distributor_id,
         sum(fdos_plan) as fdos_plan,
         sum(fdis_plan) as fdis_plan,
         sum(salfo)     as salfo
  from metrics
  group by year_upload, period_upload, year, period, channel, pg_id, distributor_id
)

select a.channel,
       a.year_upload, a.period_upload,
       to_char(to_date(cast(a.period_upload as text), 'MM'), 'Mon') as periodName_upload,
       a.year, a.period,
       to_char(to_date(cast(a.period as text), 'MM'), 'Mon') as periodName,
       -- 0 = uploaded for its own month, 1 = M+1, 2 = M+2 ... the forecast vintage.
       (a.year * 12 + a.period) - (a.year_upload * 12 + a.period_upload) as lead_months,
       vsh.nsm_id, vsh.nsm_name, vsh.grsm_id, vsh.grsm_name,
       vsh.rsm_id, vsh.rsm_name, vsh.ss_id, vsh.ss_name,
       d.div_id as sbu_id, mdiv.div_nm as sbu_name,
       d.brand_id, mbrand.brand_nm as brand_name,
       d.subbrand_id, msubbrand.subbrand_nm as subbrand_name,
       d.parent_id, mparent.parent_nm as parent_name,
       d.flag_season as flag_sku,
       a.distributor_id, md.distributor_nm as distributor_name,
       a.fdos_plan, a.fdis_plan, a.salfo,
       a.pg_id, now() as loaded_at
from agg a
join pg_dim d on d.pg_id = a.pg_id
left join spx.m_division mdiv on mdiv.div_id = d.div_id
left join spx.m_brand mbrand on mbrand.brand_id = d.brand_id
-- subbrand_id is not globally unique (603 exists under brand 601 GENTLEGEN PCH and
-- brand 602 HAND SOAP), so both keys are required here.
left join spx.m_subbrand msubbrand
  on  msubbrand.subbrand_id = d.subbrand_id
  and msubbrand.brand_id    = d.brand_id
left join spx.m_parent mparent on mparent.parent_id = d.parent_id
-- LEFT, not INNER: fdis rows have no distributor at all.
left join spx.m_distributor md on md.distributor_id = a.distributor_id
left join sales_hierarchy vsh
  on vsh.pg_id = a.pg_id and vsh.distributor_id = a.distributor_id
