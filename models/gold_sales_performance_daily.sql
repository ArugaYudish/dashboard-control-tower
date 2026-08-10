{{ config(
    materialized='view'
) }}

-- Grain: one row per (sales_date, channel, product-group, distributor_id).
--
-- This is the daily SHELL, not a shim. A real daily source is coming at exactly this
-- grain and backfilled to history; when it lands it drops in here and nothing outside
-- this file moves. The contract is fixed across all three stages: same name, same grain,
-- same columns including daily_is_estimated. The service only ever asks for one
-- (year, week).
--
--   Stage 1 (now)      view over the weekly table x m_cycle3, / n_days, flag true
--   Stage 2 (arriving) table: real rows UNION ALL derived rows for weeks not yet
--                      covered, flag per row
--   Stage 3 (done)     passthrough of the real source, derived branch deleted
--
-- The moment this stops being a view it is ~61M rows and the report reads one week
-- (~590K rows). Partition by year and index (year, week) AT THAT MOMENT, not later --
-- an unindexed 18 GB heap is exactly the problem this tiering removes.
--
-- ALWAYS FILTER BY WEEK. Unfiltered, this view reproduces all ~61M rows; it is a
-- one-week read path (the M-0 current-week block), not a scan target.
--
-- The division is arithmetic, not data: every day in a week shows weekly/n_days, hence
-- daily_is_estimated = true. That flips per row at stage 2 and to false at stage 3.

with days as (                            -- row-multiplier: one row per calendar day
    select year, week, cdate::date as sales_date
    from spx.m_cycle3
)
select
    d.sales_date,                         -- daily grain (from m_cycle3)
    w.year, w.period, w.periodname, w.week,
    w.channel,
    -- org hierarchy
    w.nsm_id, w.nsm_name, w.grsm_id, w.grsm_name,
    w.rsm_id, w.rsm_name, w.ss_id, w.ss_name,
    -- product hierarchy (sbu_id == division id)
    w.sbu_id, w.sbu_name, w.division_name, w.division_group,
    w.brand_id, w.brand_name, w.subbrand_id, w.subbrand_name,
    w.parent_id, w.parent_name, w.flag_sku, w.pg_id,
    w.distributor_id, w.distributor_name,
    -- additive flows split evenly across the week's days
    w.stm_qty      / w.n_days as stm_qty,
    w.stm_value    / w.n_days as stm_value,
    w.target_qty   / w.n_days as target_qty,
    w.target_value / w.n_days as target_value,   -- feeds the Achievement cards (stm/target)
    true                      as daily_is_estimated,  -- guardrail: per-row at stage 2, false at stage 3
    w.loaded_at
from {{ ref('gold_sales_performance_weekly') }} w
join days d on d.year = w.year and d.week = w.week   -- expands 1 weekly row -> n_days rows
