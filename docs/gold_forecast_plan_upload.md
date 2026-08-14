# `gold_forecast_plan_upload` — context for future sessions

Model file: [`models/gold_forecast_plan_upload.sql`](../models/gold_forecast_plan_upload.sql)
Physical relation: `spx.gold_forecast_plan_upload` (no `alias` config — filename is the table name)
Created: 2026-08-14. **Not yet built or validated against real data** — see [Open questions](#open-questions--not-yet-validated).

---

## Why this model exists

Sales upload their forecasts **monthly**, and one upload covers **several future months**. A
February upload carries forecasts for March, April and May. The source header tables in the
`logistic` system record that as two separate period pairs:

| Column pair | Meaning |
|---|---|
| `year_upload`, `period_upload` | when the number was submitted |
| `year`, `period` | the month being forecast |

**Every other model in this repo reads pre-flattened weekly views** — `spx.v_fdos_update`,
`spx.v_fdis_update`, `spx.v_fdis_actual`, `spx.t_salfo_confirm_weekly`. Those views have already
collapsed the upload dimension away: they only tell you the *latest* state of a forecast, not who
forecast what and when.

So before this model, the project could not answer:

- How accurate is the M+1 forecast vs the M+2 vs the M+3?
- How much did the March forecast get revised between the January, February and March uploads?
- What was the forecast *as of* a given upload month (vintage / as-of reporting)?

This model is the only place that information lives. It deliberately does **not** duplicate
actuals — join to `silver_sales_performance_parent` for those.

---

## Grain — MIXED BY DESIGN. Read this before writing any query.

Two row shapes coexist in one table:

| Rows | Key | Hierarchy columns |
|---|---|---|
| `fdos_plan`, `salfo` | `(year_upload, period_upload, year, period, channel, pg_id, distributor_id)` | full — `distributor_id`, `nsm_*`, `grsm_*`, `rsm_*`, `ss_*` all populated |
| `fdis_plan` | `(year_upload, period_upload, year, period, channel, pg_id)` | **`distributor_id` and all four salesman levels are NULL** |

### Why FDIS has no distributor

`logistic.t_fdis_plan_h` and `logistic.t_fdis_marketing_h` have **no `sub_id` column**. Their PK is
`(year_upload, period_upload, year, period, wh_id, buyer_id, plant_id, ct_id, pcode, sls_div)` —
warehouse / buyer / plant, not distributor.

Nothing in the `spx` schema maps `wh_id`, `buyer_id` or `plant_id` to a `distributor_id`.
`spx.m_distributor` carries none of those three columns (verified 2026-08-14; its columns are
`flag, ct_id, sls_div, user_id, flag_new, upd_date, region_id, sls_group, type_dist, flagdirect,
sls_office, tgl_update, flagsisdima, jenis_mobil, distributor_id, distributor_nm, distributor_add1,
distributor_add2, distributor_city, distributor_id_mtx, distributor_name_mtx`).

This matches the rest of the repo: [`models/silver_performance_fdis.sql`](../models/silver_performance_fdis.sql)
also carries no distributor or salesman columns at all. `wh_id` is only ever used as an
FDIS-internal matching key, never joined to a dimension. `buyer_id` and `plant_id` appear **zero
times** anywhere in the repo.

> If someone later confirms `buyer_id` *is* the distributor code, the fix is a one-line change:
> join `buyer_id` to `m_distributor.distributor_id` in the `fdis` CTE and drop the
> `null::varchar as distributor_id`. Do not assume this without checking the logistic system.

### Consequences

1. **A filter on `distributor_id` / `ss_id` / `rsm_id` / `grsm_id` / `nsm_id` silently drops every
   `fdis_plan` row.** Superset dashboards that put a distributor filter on this dataset will show
   FDIS as zero, with no error. Warn the dashboard author.
2. Each metric is safe to `SUM` on its own.
3. The three metrics are only comparable when sliced at **product × channel × period** or coarser.

### No `week` column

All four sources are monthly. There is no week key anywhere in them, and none is synthesised.
This is the one place this model's shape departs from `silver_sales_performance_parent`.

---

## Where the data comes from

Two separate Postgres servers are in play:

| | Host | DB | Role |
|---|---|---|---|
| **BI / dbt target** | `10.2.50.108` | `snopixbi`, schema `spx` | what this project builds into; profile `dashboard` in `~/.dbt/profiles.yml` |
| **Operational source** | `10.2.50.91` | `logistic` | where the `t_*_h` tables actually originate; profile `snopix_sff`, used by a *different* project |

**Airbyte replicates `logistic` tables into `spx` under their original names.** That is why
`spx.t_salfo_confirm_weekly` and `spx.v_fdos_update` are `BASE TABLE`s in `snopixbi` despite the
`v_` prefix — they are snapshots of source views, not views. Every replicated table carries four
extra columns: `_airbyte_raw_id`, `_airbyte_extracted_at`, `_airbyte_meta`, `_airbyte_generation_id`.

This model reads four **new** Airbyte streams, added for it:

| Model reads | Origin |
|---|---|
| `spx.t_fdos_h` | `logistic.t_fdos_h` |
| `spx.t_fdis_plan_h` | `logistic.t_fdis_plan_h` |
| `spx.t_fdis_marketing_h` | `logistic.t_fdis_marketing_h` |
| `spx.v_t_salfo_confirm_h` | `logistic.t_salfo_confirm_h`, via a trimming view |

`spx.v_t_salfo_confirm_h` is **not** a straight copy of the header table. It is pre-trimmed to
`(year_upload, period_upload, year, period, pcode, distributor_id, qty)` — the distributor key is
already named `distributor_id` rather than `sub_id`, and `type_id`, `ct_id`, `wh_id`, `buyer_id`,
`plant_id`, `flag_proc` and the audit columns are all dropped. That matters: unlike `t_fdos_h`,
there is no hidden fan-out being summed over on the SALFO side.

`dbt compile` works whether or not these exist (they are schema-qualified raw tables, not `ref()`s),
but `dbt run` will fail until they land. Check with:

```sql
select table_name from information_schema.tables
where table_schema = 'spx'
  and table_name in ('t_fdos_h','t_fdis_plan_h','t_fdis_marketing_h','v_t_salfo_confirm_h');
```

> Naming note: the original request said `t_fdis_h`, but the DDL supplied was for `t_fdis_plan_h`,
> and that is what the model uses. If a distinct `t_fdis_h` also exists, revisit the `fdis` CTE.

---

## Metric definitions

| Output column | Source | Expression |
|---|---|---|
| `fdos_plan` | `spx.t_fdos_h` | `sum(coalesce(qty, 0))` |
| `fdis_plan` | `spx.t_fdis_marketing_h` **FULL OUTER** `spx.t_fdis_plan_h` | `sum(coalesce(m.qty_final, p.qty))` |
| `salfo` | `spx.v_t_salfo_confirm_h` | `sum(coalesce(qty, 0))` |

Columns deliberately **not** used, and why:

- `t_fdos_h.qty_adj` / `persen_adj` / `flag_adj` / `qty_salfo` — the plain uploaded `qty` was chosen.
  (`v_t_salfo_confirm_h` exposes no alternative qty column, so SALFO has no equivalent choice.)
  Switch to `case when flag_adj = 1 then qty_adj else qty end` if the business wants the adjusted number.
- `t_fdis_marketing_h.qty_konsolidasi` / `qty_marketing` — `qty_final` is marketing's last word and wins.
  `qty_marketing` is the intermediate step.

**Why FULL OUTER for FDIS:** `t_fdis_marketing_h` and `t_fdis_plan_h` share an identical 10-column
PK but do not cover the same key set in either direction — a period can have a marketing row with no
plan row and vice versa. A LEFT join from either side would drop real forecasts. Every key column is
`coalesce`d, not just the qty.

---

## Column reference

Order follows the shape of `silver_sales_performance_parent`, with the upload columns leading and
`lead_months` / `pg_id` / `loaded_at` appended.

| Column | Source |
|---|---|
| `channel` | `m_distributor.sls_div` (fdos/salfo) or `t_fdis_*.sls_div` (fdis) |
| `year_upload`, `period_upload` | source tables |
| `periodName_upload` | `to_char(to_date(cast(period_upload as text),'MM'),'Mon')` |
| `year`, `period` | source tables |
| `periodName` | same `to_char` idiom — the repo-wide convention, `1 -> 'Jan'` |
| `lead_months` | `(year*12 + period) - (year_upload*12 + period_upload)`. `0` = uploaded for its own month, `1` = M+1, etc. **This is the forecast-vintage filter.** |
| `nsm_id/name`, `grsm_id/name`, `rsm_id/name`, `ss_id/name` | `sales_hierarchy` CTE ← `spx.v_sales_hierarchy_product`, joined on `(pg_id, distributor_id)` |
| `sbu_id`, `sbu_name` | `m_product.div_id` → `spx.m_division.div_nm` |
| `brand_id`, `brand_name` | `spx.m_brand` |
| `subbrand_id`, `subbrand_name` | `spx.m_subbrand` — **joined on BOTH `subbrand_id` AND `brand_id`** |
| `parent_id`, `parent_name` | `spx.m_parent` |
| `flag_sku` | `m_product.flag_season` |
| `distributor_id` | `t_fdos_h.sub_id` / `v_t_salfo_confirm_h.distributor_id`; NULL on fdis rows |
| `distributor_name` | `spx.m_distributor.distributor_nm` |
| `fdos_plan`, `fdis_plan`, `salfo` | see above |
| `pg_id` | product-group surrogate — join key to `silver_sales_performance_parent` |
| `loaded_at` | `now()` |

---

## Repo conventions this model inherits

These are load-bearing. Do not "simplify" them away.

### 1. `pg_id`, not `parent_id`

The `pre_hook` builds two ANALYZEd temp tables, copied verbatim from
[`silver_sales_performance_parent.sql`](../models/silver_sales_performance_parent.sql):

- `tmp_pg_dim` — `row_number()` surrogate over `distinct (div_id, brand_id, subbrand_id, parent_id, flag_season)` from `spx.m_product where parent_id is not null`
- `tmp_pcode_pg` — `pcode → pg_id`

Two reasons, both documented in the parent model:

- **Correctness.** Rolling metrics up on `parent_id` alone *copies* a parent-level value onto each of
  its product groups instead of splitting it — up to 5× inflation, 123 of 1876 parents affected.
- **Planner statistics.** They are temp tables re-exposed as `not materialized` CTEs so the planner
  sees real row counts instead of estimating `rows=1` and choosing nested loops. Inlining them as
  ordinary CTEs was measurably slower.

dbt gives each model its own connection, so **the temp tables must be rebuilt in this model's own
`pre_hook`** — they do not carry over from the parent model's run. Because `pg_id` is a
`row_number()` over the same deterministic ordering of the same `m_product` rows, the ids match
across both models, which is what makes `pg_id` a valid join key between them.

### 2. The two-key subbrand join

```sql
left join spx.m_subbrand msubbrand
  on  msubbrand.subbrand_id = d.subbrand_id
  and msubbrand.brand_id    = d.brand_id
```

`subbrand_id` is **not globally unique** — `603` exists under both brand `601` (GENTLEGEN PCH) and
brand `602` (HAND SOAP). A single-key join fans rows out.

### 3. `sales_hierarchy` uses `distinct on`, not `select distinct`

73 `(pcode, distributor)` keys map to two salesmen (Beverage, `div_id` 10). Only `ss_id` differs —
`nsm`/`grsm`/`rsm` are identical within every affected key — so `distinct on (pg_id, distributor_id)
... order by pg_id, distributor_id, ss_id nulls last` picks one stable `ss_id` and nothing above
salesman moves. The looser `select distinct` form in
[`silver_performance_fdos.sql`](../models/silver_performance_fdos.sql) duplicates those rows.

### 4. Stacked `union all` instead of a key spine

`silver_sales_performance_parent` uses a `union` key spine plus one `left join` per metric. This
model cannot: `distributor_id` is NULL on every fdis row, so those joins would need
`is not distinct from`, which is not hash-joinable. Instead the three metric CTEs are stacked long-form
with zero-fills and aggregated once. `group by` puts the NULL distributor in its own group — exactly
the separation the mixed grain needs.

### 5. No `m_cycle3`

Every other fact model in this repo joins `spx.m_cycle3` to resolve `week → period`. This one has no
week, and `period` comes straight from the source, so it does not join the calendar at all. That is
intentional, not an oversight.

### 6. Scope filter

All three metric CTEs filter `year_upload >= extract(year from current_date) - 1`. **No upper bound**
— plans legitimately point into the future, and an upper bound would silently truncate them.

---

## Open questions — NOT YET VALIDATED

The model was written from DDL, not from data. Resolve these before anyone trusts the totals.

### `t_fdos_h.type_id` is summed over, not filtered — highest risk

`t_fdos_h` carries `type_id` in its PK and the model sums across it. **If `type_id` marks plan
*versions* rather than additive categories, `fdos_plan` double-counts.**

```sql
select type_id, count(*), sum(qty) from spx.t_fdos_h group by type_id order by 1;
```

If more than one `type_id` carries meaningful volume for the same
`(sub_id, pcode, year_upload, period_upload, year, period)`, add a filter to the `fdos` CTE.

The same question applies to `ct_id`, `wh_id`, `buyer_id` and `plant_id`, which are also summed over.

**SALFO is not exposed to this** — `spx.v_t_salfo_confirm_h` drops `type_id` and the four
location/company keys upstream, so its grain is already
`(year_upload, period_upload, year, period, pcode, distributor_id)`. Worth confirming once, though,
that the upstream view aggregated rather than arbitrarily picked a row.

### `t_fdos_h.flag_proc` / `flag_upload` are ignored

Drafts and unprocessed rows are currently included. `v_t_salfo_confirm_h` does not expose these
columns at all, so whatever filtering the upstream view applies is what SALFO gets.

```sql
select flag_proc, flag_upload, count(*) from spx.t_fdos_h group by 1,2 order by 1,2;
```

### `t_fdis_plan_h` approval columns are ignored

`status_approval_1/2/3`, `cancel_reason`, `docno` — the model takes `qty` regardless of approval
state. Confirm whether unapproved or cancelled plans should be excluded.

---

## How to build and verify

```bash
cd d:/MYOR/0Repo/dashboard-control-tower
dbt run --select gold_forecast_plan_upload
```

Profile `dashboard` → `snopixbi` @ `10.2.50.108`, schema `spx`. Full rebuild each run; there are no
incremental models anywhere in this project.

**1. Grain uniqueness** — must return zero rows:

```sql
select year_upload, period_upload, year, period, channel, pg_id, distributor_id, count(*)
from spx.gold_forecast_plan_upload
group by 1,2,3,4,5,6,7 having count(*) > 1;
```

**2. The mixed-grain invariants** — both must return `0`:

```sql
select count(*) from spx.gold_forecast_plan_upload
where distributor_id is null and (fdos_plan <> 0 or salfo <> 0);

select count(*) from spx.gold_forecast_plan_upload
where distributor_id is not null and fdis_plan <> 0;
```

**3. Multi-month uploads actually materialise.** Expect `lead_months` mostly in `0..3` and **no
negative values** — a plan for a month before its own upload means a source problem:

```sql
select year_upload, period_upload, lead_months, count(*) as rows,
       sum(fdos_plan) as fdos, sum(fdis_plan) as fdis, sum(salfo) as salfo
from spx.gold_forecast_plan_upload
group by 1,2,3 order by 1,2,3;
```

**4. Reconcile SALFO against the weekly view.** Take the *latest* vintage per target period and
compare to `silver_sales_performance_parent`. They will not match exactly — the weekly view reflects
the latest confirmed state, not every vintage — but they should be in the same ballpark:

```sql
select p.year, p.period, sum(p.salfo) as plan_salfo
from spx.gold_forecast_plan_upload p
join (select year, period, max(year_upload*100 + period_upload) as mx
      from spx.gold_forecast_plan_upload group by 1,2) l
  on l.year = p.year and l.period = p.period
 and l.mx  = p.year_upload*100 + p.period_upload
group by 1,2 order by 1,2;

select year, period, sum(salfo_qty)
from spx.silver_sales_performance_parent group by 1,2 order by 1,2;
```

**5. Row-count sanity.** Roughly `#upload periods × ~4 target periods × #pg × #distributor` populated
combinations. A blow-up points at the `type_id` fan-out above.

---

## Related models

| Model | Relationship |
|---|---|
| [`silver_sales_performance_parent.sql`](../models/silver_sales_performance_parent.sql) | The actuals counterpart. Same `pg_id`, same dimension joins, weekly grain. **Join on `pg_id`**, not the five product-attribute columns. |
| [`silver_performance_fdis.sql`](../models/silver_performance_fdis.sql) | Weekly FDIS plan-vs-actual at parent grain, from `v_fdis_update` / `v_fdis_actual`. Also has no distributor — same root cause. |
| [`silver_performance_fdos.sql`](../models/silver_performance_fdos.sql) | Weekly FDOS vs STA at `(distributor, parent)` grain, from `v_fdos_update`. |
| [`gold_forecast_kpi_detail.sql`](../models/gold_forecast_kpi_detail.sql) | alias `gold_forecast_kpi_by_period`. Forecast accuracy from `silver_sales_performance_parent`: `total_forecast = sum(salfo_qty)` vs `total_actual = sum(stm_qty)`. **This is the natural consumer** — `gold_forecast_plan_upload` can extend it with per-vintage accuracy. |
| `gold_sales_target_performance.sql` | **Deprecated / unmaintained.** Hardcodes TY=2026/LY=2025 and drops `period` from its TY↔LY join key. Do not build on it, but do not delete it either — Superset datasets may still query it. |

## Known caveat inherited from silver

`cycle_ranked` in `silver_sales_performance_parent` groups `spx.m_cycle3` by `(year, week, period)`
but every consumer joins it on `(year, week)` only, so a week straddling two periods is emitted
twice. Relevant when reconciling against silver in step 4 above. Confirm with:

```sql
select year, week, count(*) from spx.m_cycle3
group by year, week having count(distinct period) > 1;
```

This model is unaffected — it never touches `m_cycle3`.
