{{ config(
    materialized='incremental',
    schema='bift',
    pre_hook=[
      "{% if is_incremental() %}
         -- Sapu bersih data 60 hari terakhir di tabel target untuk M2 dan M3
         DELETE FROM {{ this }}
         WHERE tgl >= CURRENT_DATE - INTERVAL '60 DAY'
           AND source_schema IN ('m2', 'm3');
       {% endif %}"
    ]
) }}

with source_m2 as (

    select
        'm2'::text as source_schema,
        *
    from raw_ficom_m2.v_nmrc_subdetail
    where tgl >= '2026-03-01'
    {% if is_incremental() %}
        -- Ambil data 60 hari terakhir sesuai view staging
        and tgl >= CURRENT_DATE - INTERVAL '60 DAY'
    {% endif %}

),

source_m3 as (

    select
        'm3'::text as source_schema,
        *
    from raw_ficom_m3.v_nmrc_subdetail
    where tgl >= '2026-03-01'
    {% if is_incremental() %}
        -- Ambil data 60 hari terakhir sesuai view staging
        and tgl >= CURRENT_DATE - INTERVAL '60 DAY'
    {% endif %}

),

unioned as (

    select * from source_m2
    union all
    select * from source_m3

)

select * from unioned