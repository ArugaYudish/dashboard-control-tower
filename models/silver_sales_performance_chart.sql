{{ config(
    materialized='table',
    post_hook=[
      "CREATE INDEX IF NOT EXISTS ix_sspc ON {{ this }} (\"year\", channel, \"period\", week, parent_id, distributor_id)"
    ]
) }}

with base as (
  select
    channel, "year"::int as year, "period"::int as "period", periodname, week::int as week,
    nsm_id, nsm_name, grsm_id, grsm_name, rsm_id, rsm_name,
    ss_id, ss_name, sbu_id, sbu_name, brand_id, brand_name,
    subbrand_id, subbrand_name, parent_id, parent_name,
    flag_sku,
    distributor_id, distributor_name,
    target_qty, salfo_qty, sta_qty, stm_qty,
    stock_qty as stock_subdist, stock_ibn,
    stock_qty / nullif(avg_5w_qty, 0) * 6     as scd_subdist_ratio,
    stock_ibn     / nullif(avg_5w_sta_qty, 0) * 6 as scd_ibn_ratio
  from {{ ref('silver_sales_performance_parent') }}
),

years_in_data as (
  select distinct year from base
),

-- Part 1: every current-year row, with stm_prev pulled from matching prev-year row
cy_rows as (
  select
    cy.year,
    cy.channel, cy."period", cy.periodname, cy.week,
    cy.nsm_id, cy.nsm_name, cy.grsm_id, cy.grsm_name, cy.rsm_id, cy.rsm_name,
    cy.ss_id, cy.ss_name, cy.sbu_id, cy.sbu_name, cy.brand_id, cy.brand_name,
    cy.subbrand_id, cy.subbrand_name, cy.parent_id, cy.parent_name,
    cy.flag_sku,
    cy.distributor_id, cy.distributor_name,
    cy.target_qty    as budget,
    cy.salfo_qty     as salfo,
    cy.sta_qty       as sta,
    cy.stm_qty       as stm_current,
    py.stm_qty       as stm_prev,
    cy.stock_subdist,
    cy.stock_ibn,
    cast(cy.scd_subdist_ratio + cy.scd_ibn_ratio as float) as scd
  from base cy
  left join base py
    on  py.year          = cy.year - 1
    and py.channel       = cy.channel
    and py."period"      = cy."period"
    and py.week          = cy.week
    and py.parent_id     = cy.parent_id
    and py.distributor_id = cy.distributor_id
),

-- Part 2: prev-year weeks with NO matching current-year row
-- e.g. 2025 week 27-52 when cy=2026 — shows stm_current as NULL
py_orphan_rows as (
  select
    (py.year + 1)::int as year,   -- ref_year = the cy the user will filter on
    py.channel, py."period", py.periodname, py.week,
    py.nsm_id, py.nsm_name, py.grsm_id, py.grsm_name, py.rsm_id, py.rsm_name,
    py.ss_id, py.ss_name, py.sbu_id, py.sbu_name, py.brand_id, py.brand_name,
    py.subbrand_id, py.subbrand_name, py.parent_id, py.parent_name,
    py.flag_sku,
    py.distributor_id, py.distributor_name,
    null::numeric  as budget,
    null::numeric  as salfo,
    null::numeric  as sta,
    null::numeric  as stm_current,
    py.stm_qty     as stm_prev,
    null::numeric  as stock_subdist,
    null::numeric  as stock_ibn,
    null::float    as scd
  from base py
  -- only generate orphan rows when the next year actually exists in data
  inner join years_in_data yid on yid.year = py.year + 1
  -- exclude rows that already have a cy counterpart (handled in Part 1)
  where not exists (
    select 1 from base cy
    where cy.year          = py.year + 1
      and cy.channel       = py.channel
      and cy."period"      = py."period"
      and cy.week          = py.week
      and cy.parent_id     = py.parent_id
      and cy.distributor_id = py.distributor_id
  )
)

select *, now() as loaded_at from cy_rows
union all
select *, now() as loaded_at from py_orphan_rows