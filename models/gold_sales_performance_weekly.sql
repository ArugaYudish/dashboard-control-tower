{{ config(
    materialized='table',
    post_hook=[
      "CREATE INDEX IF NOT EXISTS ix_gspw_ypw ON {{ this }} (\"year\", \"period\", week)",
      "CREATE INDEX IF NOT EXISTS ix_gspw_yw  ON {{ this }} (\"year\", week)",
      "ANALYZE {{ this }}"
    ]
) }}

-- Grain: one row per (year, week, channel, product-group, distributor_id) -- i.e.
-- silver's own grain, no longer expanded to daily. This is the base tier: the monthly
-- aggregate rolls up from it and the daily model fans back out of it.
--
-- week_start/n_days come along so the daily model can divide, and so the report can
-- order mixed-granularity buckets chronologically (week_start is the week's col_order).
--
-- Source is silver_sales_performance_parent, whose smallest product key is the product
-- group (div_id, brand_id, subbrand_id, parent_id, flag_season) surfaced as pg_id -- so
-- pcode and pcodename are gone. A parent whose SKUs span several subbrands still yields
-- one row per group, with each group carrying its own share of the metrics, so sums stay
-- exact at parent level. target_qty/target_value only exist at parent grain upstream and
-- are pinned to one designated group per parent (NULL on the others) -- sum them, never
-- average.
--
-- Indexes exist because the report reads narrow slices: a whole period (M-1), a period
-- up to a week (M-0, YTD), or a single week (the daily fan-out join).

with week_bounds as (                     -- one row per (year, week)
    select year, week,
           min(cdate::date) as week_start,   -- first calendar day of the week
           count(*)         as n_days        -- divisor for the daily model
    from spx.m_cycle3
    group by year, week
)
select
    s.year, s.period, s.periodname, s.week,
    wb.week_start,                        -- drives col_order for weekly buckets
    wb.n_days,                            -- divisor for the daily model
    s.channel,
    -- org hierarchy
    s.nsm_id, s.nsm_name, s.grsm_id, s.grsm_name,
    s.rsm_id, s.rsm_name, s.ss_id, s.ss_name,
    -- product hierarchy (sbu_id == division id)
    s.sbu_id, s.sbu_name,
    dv.div_nm                        as division_name,
    coalesce(dg.m_group, 'UNMAPPED') as division_group,   -- 11 Industrial etc. -> visible, not dropped
    s.brand_id, s.brand_name, s.subbrand_id, s.subbrand_name,
    s.parent_id, s.parent_name, s.flag_sku,
    s.pg_id,                              -- product-group surrogate: smallest product key
    s.distributor_id, s.distributor_name,
    -- weekly totals, NOT divided: the fan-out is what this model removes
    s.stm_qty, s.stm_value,
    s.target_qty, s.target_value,         -- feeds the Achievement cards (stm/target)
    current_timestamp                as loaded_at
from spx.silver_sales_performance_parent s
join      week_bounds wb on wb.year = s.year and wb.week = s.week
left join spx.m_division dv on dv.div_id = s.sbu_id
left join {{ ref('division_group_map') }} dg on dg.div_id = s.sbu_id::varchar
-- Drops ~2.16M silver rows carrying no sales and no target (24.7%). Safe for a report
-- that only SUMs; check other consumers before relying on it, since a row meaning
-- "stocked nothing this week" disappears. Better still, fix it in silver.
where coalesce(s.stm_value, 0) <> 0 or coalesce(s.target_value, 0) <> 0
