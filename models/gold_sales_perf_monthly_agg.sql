{{ config(
    materialized='table',
    post_hook=[
      "CREATE INDEX IF NOT EXISTS ix_gspma_yp ON {{ this }} (\"year\", \"period\")",
      "ANALYZE {{ this }}"
    ]
) }}

-- Report-serving aggregate, NOT a general gold layer: distributor_id and pg_id are
-- dropped, so don't point Superset at this expecting them. Use it for the monthly
-- columns (Jan .. M-2) and for the whole-period part of YTD.
--
-- Rolling weekly up to period is exact because no week straddles a period in
-- spx.m_cycle3 (verified, 0 violations) -- every week belongs to exactly one period.
--
-- target_qty/target_value are pinned to one product group per parent upstream, so
-- summing them here is correct; averaging would not be.

select
    year, period,
    max(periodname)               as periodname,
    min(week_start)               as period_start,   -- drives col_order for monthly buckets
    channel, division_group,
    sbu_id, sbu_name, brand_id, brand_name,
    subbrand_id, subbrand_name, parent_id, parent_name,
    nsm_id, nsm_name, grsm_id, grsm_name,
    rsm_id, rsm_name, ss_id, ss_name,
    sum(stm_qty)      as stm_qty,
    sum(stm_value)    as stm_value,
    sum(target_qty)   as target_qty,
    sum(target_value) as target_value,
    current_timestamp as loaded_at
from {{ ref('gold_sales_performance_weekly') }}
group by
    year, period, channel, division_group,
    sbu_id, sbu_name, brand_id, brand_name,
    subbrand_id, subbrand_name, parent_id, parent_name,
    nsm_id, nsm_name, grsm_id, grsm_name,
    rsm_id, rsm_name, ss_id, ss_name
