# Handoff: `gold_sales_performance_daily` moved from pcode grain to parent/product-group grain

**Date:** 2026-08-10
**File changed:** `models/gold_sales_performance_daily.sql` (only this file)
**Status:** edited, `dbt parse` clean, **not run** — the table has not been rebuilt yet.

---

## TL;DR

The model's source was swapped from `spx.silver_sales_performance` (one row per **pcode**) to
`spx.silver_sales_performance_parent` (one row per **product group**). `pcode` and `pcodename`
are gone from the output; `pg_id` was added in their place. Nothing else about the model's
logic changed — the weekly→daily fan-out and the divisor arithmetic are untouched.

---

## The diff

```diff
+-- Grain: one row per (sales_date, channel, product-group, distributor_id).
+-- ...see the header comment in the model for the full note...

     s.brand_id, s.brand_name, s.subbrand_id, s.subbrand_name,
-    s.parent_id, s.parent_name, s.pcode, s.pcodename, s.flag_sku,
+    s.parent_id, s.parent_name, s.flag_sku,
+    s.pg_id,                              -- product-group surrogate: the new smallest product key
     s.distributor_id, s.distributor_name,

-from spx.silver_sales_performance s
+from spx.silver_sales_performance_parent s
```

Three edits total: header comment, select-list swap, `from` clause.

---

## Why `pg_id` and not just `parent_id`

This is the part most likely to trip up the next change, so read it before touching the model.

`silver_sales_performance_parent`'s smallest key is **not** `parent_id`. It is the *product group*:

```
(div_id, brand_id, subbrand_id, parent_id, flag_season)  ->  surrogate integer pg_id
```

Full grain of the silver model: `(year, channel, period, week, pg_id, distributor_id)`.

That design is deliberate and is documented in the silver model's own header. The earlier version
of that model selected distinct product groups but joined metrics on `parent_id` alone, so a parent
whose SKUs span more than one subbrand had its single parent-level value **copied** onto each group
row — inflating every sum by up to 5x, across 123 of 1876 parents. The `pg_id` grain fixes that by
splitting metrics across groups instead of copying them.

Consequences for this gold model:

- A parent can still produce **multiple rows per day per distributor** (one per product group).
- Those rows carry *disjoint shares* of the metrics, so `sum(stm_value)` at parent level is exact.
- The brand / subbrand columns remain meaningful and filterable, which is why the model keeps them
  rather than collapsing to one row per parent.

If someone actually wants strictly one row per `parent_id` per day, that is an additional
`group by` layered on top of the current select — it is **not** what this change did.

---

## Column mapping

| Old (`silver_sales_performance`) | New (`silver_sales_performance_parent`) | Note |
|---|---|---|
| `pcode`, `pcodename` | — | **Removed.** This is the grain change. |
| — | `pg_id` | **Added.** Product-group surrogate key. |
| `flag_sku` | `flag_sku` | Upstream it is `flag_season`, already aliased in silver. |
| `year, period, periodname, week, channel` | same | |
| `nsm_*, grsm_*, rsm_*, ss_*` | same | |
| `sbu_id, sbu_name, brand_*, subbrand_*, parent_*` | same | |
| `distributor_id, distributor_name` | same | |
| `stm_qty, stm_value, target_qty, target_value` | same | |

Every retained column was verified to exist under the same name in the new source.

Also available upstream but **not** selected, in case they are wanted later: `flag_direct`,
`salfo_*`, `stock_*`, `sta_*`, `fdos_*`, `avg_5w_*`, `avg_13w_*`, `stock_ibn*`, `flag`.

---

## Gotchas for whoever picks this up

1. **`target_qty` / `target_value` are pinned, not spread.** Targets only exist at parent grain
   upstream (`v_target_weekly_by_parent` has no pcode), so silver attaches them to *one designated
   product group per parent* (`min(pg_id)`) and leaves them NULL on the others. **Sum them; never
   average them.** Filtering to a single subbrand can legitimately return rows with a NULL target.

2. **`materialized='table'`.** A `dbt run` replaces the table outright. The moment it runs,
   `pcode` and `pcodename` disappear from the physical table. Any Superset dataset column, filter,
   chart, or saved query referencing them breaks. **Nothing in this repo references
   `gold_sales_performance_daily`** (verified by grep across `models/`, excluding `target/`), so
   the entire blast radius is Superset-side. Check Superset before running.

3. **Row count should drop a lot.** Rolling up from pcode to product group is the whole point.
   If the row count is roughly unchanged after a rebuild, something is wrong.

4. **Daily values are still estimates.** Pre-existing behaviour, unchanged: weekly measures are
   divided by `n_days` from `spx.m_cycle3` and fanned out across the week's calendar days.
   `daily_is_estimated = true` is the guardrail flag — flip it when real daily data lands.

5. **`division_name` duplicates `sbu_name`.** The model left-joins `spx.m_division` to produce
   `division_name`, but silver already derives `sbu_name` from the same table on the same key, so
   the two columns are identical. This was equally true before the change; left alone deliberately
   to avoid widening the scope.

---

## Verification done / not done

- Done: read both silver models, confirmed every retained column exists in the new source,
  confirmed no in-repo dependents, `dbt parse --no-version-check` runs clean.
- Not done: `dbt run` (table not rebuilt), row-count comparison, Superset impact audit,
  any reconciliation of `sum(stm_value)` old vs new.

The natural next step is a rebuild in a scratch schema plus an old-vs-new `sum(stm_value)` and
`sum(target_value)` comparison per `(year, week, parent_id)` — those should match to rounding if
the change is correct.
