{%- set v_all_periods = var('all_periods', false) -%}
{%- set ns = namespace(has_data=true) -%}
{%- if execute and not v_all_periods -%}
    {%- set rel = adapter.get_relation(database=target.dbname, schema='spx', identifier='vfsales_det') -%}
    {%- if rel is none -%}
        {%- set ns.has_data = false -%}
    {%- else -%}
        {%- set res = run_query("SELECT EXISTS (SELECT 1 FROM spx.vfsales_det LIMIT 1)") -%}
        {%- set ns.has_data = res.columns[0].values()[0] if (res and (res.rows | length) > 0) else false -%}
    {%- endif -%}
{%- endif -%}

{{
  config(
    materialized='incremental',
    schema='spx',
    pre_hook=[
      "{{ vfsales_delete_recent_window(10) }}"
    ]
  )
}}

select
    *
from raw_ho.vfsales_det

{% if is_incremental() and not v_all_periods and ns.has_data %}
    where inv_date >= CURRENT_DATE - INTERVAL '10 DAY'
{% endif %}