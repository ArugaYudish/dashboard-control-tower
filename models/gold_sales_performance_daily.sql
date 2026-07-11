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
    s.parent_id, s.parent_name, s.pcode, s.pcodename, s.flag_sku,
    s.distributor_id, s.distributor_name,
    -- additive flows split evenly across the week's days
    s.stm_qty   / wd.n_days         as stm_qty,
    s.stm_value / wd.n_days         as stm_value,
    true                            as daily_is_estimated,  -- guardrail: flip false when real daily lands
    current_timestamp               as loaded_at
from spx.silver_sales_performance s
join week_days wd on wd.year = s.year and wd.week = s.week
join days     d  on d.year  = s.year and d.week  = s.week   -- expands 1 weekly row -> n_days rows
left join spx.m_division dv on dv.div_id = s.sbu_id
left join {{ ref('division_group_map') }} dg on dg.div_id = s.sbu_id