{{ config(
    materialized='table'
) }}

-- Grain: one row per (sales_date, channel, product-group, distributor_id).
-- Source moved from silver_sales_performance (pcode grain) to
-- silver_sales_performance_parent, whose smallest product key is the product group
-- (div_id, brand_id, subbrand_id, parent_id, flag_season) surfaced as pg_id -- so pcode
-- and pcodename are gone. A parent whose SKUs span several subbrands still yields one row
-- per group, with each group carrying its own share of the metrics, so sums stay exact at
-- parent level. target_qty/target_value only exist at parent grain upstream and are pinned
-- to one designated group per parent (NULL on the others) -- sum them, never average.

with week_days as (                       -- divisor: how many days in each (year, week)
    select year, week, count(*) as n_days
    from spx.m_cycle3
    group by year, week
),
days as (                                 -- row-multiplier: one row per calendar day
    select year, week, cdate::date as sales_date
    from spx.m_cycle3
)
select
    d.sales_date,                         -- NEW daily grain (from m_cycle3)
    s.year, s.period, s.periodname, s.week,
    s.channel,
    -- org hierarchy
    s.nsm_id, s.nsm_name, s.grsm_id, s.grsm_name,
    s.rsm_id, s.rsm_name, s.ss_id, s.ss_name,
    -- product hierarchy (sbu_id == division id)
    s.sbu_id, s.sbu_name,
    dv.div_nm                       as division_name,
    coalesce(dg.m_group, 'UNMAPPED') as division_group,   -- 11 Industrial etc. -> visible, not dropped
    s.brand_id, s.brand_name, s.subbrand_id, s.subbrand_name,
    s.parent_id, s.parent_name, s.flag_sku,
    s.pg_id,                              -- product-group surrogate: the new smallest product key
    s.distributor_id, s.distributor_name,
    -- additive flows split evenly across the week's days
    s.stm_qty      / wd.n_days      as stm_qty,
    s.stm_value    / wd.n_days      as stm_value,
    s.target_qty   / wd.n_days      as target_qty,
    s.target_value / wd.n_days      as target_value,     -- feeds the Achievement cards (stm/target)
    true                            as daily_is_estimated,  -- guardrail: flip false when real daily lands
    current_timestamp               as loaded_at
from spx.silver_sales_performance_parent s
join week_days wd on wd.year = s.year and wd.week = s.week
join days     d  on d.year  = s.year and d.week  = s.week   -- expands 1 weekly row -> n_days rows
left join spx.m_division dv on dv.div_id = s.sbu_id
left join {{ ref('division_group_map') }} dg on dg.div_id = s.sbu_id::varchar