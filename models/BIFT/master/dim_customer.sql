{%- set v_all_periods = var('all_periods', false) -%}
{%- set v_lookback_days = var('lookback_days', 35) | int -%}
{%- set ns = namespace(has_data=true) -%}
{%- if execute and not v_all_periods -%}
    {%- set rel = adapter.get_relation(database=target.dbname, schema='bift', identifier='dim_customer') -%}
    {%- if rel is none -%}
        {%- set ns.has_data = false -%}
    {%- else -%}
        {%- set res = run_query("SELECT EXISTS (SELECT 1 FROM bift.dim_customer LIMIT 1)") -%}
        {%- set ns.has_data = res.columns[0].values()[0] if (res and (res.rows | length) > 0) else false -%}
    {%- endif -%}
{%- endif -%}

{{
    config(
        schema='bift',
        materialized='incremental',
        alias='dim_customer',
        incremental_strategy='delete+insert',
        unique_key=['subdist_id', 'custno'],
        pre_hook=[
            "SET LOCAL work_mem = '256MB'",
            "{% if is_incremental() and var('all_periods', false) %} TRUNCATE TABLE {{ this }}; {% endif %}"
        ],
        indexes=[
            {'columns': ['subdist_id', 'custno'], 'type': 'btree'}
        ]
    )
}}

select
    *
from raw_ho.fcustmst
where custno is not null 
  and subdist_id is not null
{% if is_incremental() and not v_all_periods and ns.has_data %}
  -- Ambil data master customer yang di-update dalam 35 hari terakhir (atau semua jika tabel di-truncate)
  and clastupd >= CURRENT_DATE - INTERVAL '{{ v_lookback_days }} DAY'
{% endif %}