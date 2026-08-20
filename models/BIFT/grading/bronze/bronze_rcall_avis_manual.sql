{{ config(
    materialized='incremental',
    schema='spx',
    pre_hook=[
      "{% if is_incremental() %}
         -- Sapu bersih data 30 hari terakhir di tabel target untuk M2 dan M3
         DELETE FROM {{ this }}
         WHERE visit_date >= CURRENT_DATE - INTERVAL '30 DAY'
           AND source_schema IN ('m2', 'm3');
       {% endif %}"
    ]
) }}

with source_m2 as (

    select
        'm2'::text as source_schema,
        *
    from raw_ficom_m2.v_rcall_avis_manual
    where visit_date >= '2026-03-01'
    {% if is_incremental() %}
        -- Ambil data 30 hari terakhir sesuai view staging
        and visit_date >= CURRENT_DATE - INTERVAL '30 DAY'
    {% endif %}

),

source_m3 as (

    select
        'm3'::text as source_schema,
        *
    from raw_ficom_m3.v_rcall_avis_manual
    where visit_date >= '2026-03-01'
    {% if is_incremental() %}
        -- Ambil data 30 hari terakhir sesuai view staging
        and visit_date >= CURRENT_DATE - INTERVAL '30 DAY'
    {% endif %}

),

unioned as (

    select * from source_m2
    union all
    select * from source_m3

)

select * from unioned