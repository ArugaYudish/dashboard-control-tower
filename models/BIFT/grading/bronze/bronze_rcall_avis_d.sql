{{ config(
    materialized='incremental',
    unique_key=[
        'source_schema',
        'distributor_id',
        'sls_id',
        'outlet_id',
        'visit_date',
        'kode_ap',
        'pcode'
    ]
) }}

with source_m2 as (

    select
        'm2' as source_schema,
        *
    from raw_ficom_m2.t_rcall_avis_d
    where visit_date > '2026-03-01'
    {% if is_incremental() %}
      and visit_date > (select coalesce(max(visit_date), '1970-01-01') from {{ this }} where source_schema = 'm2')
    {% endif %}

),

source_m3 as (

    select
        'm3' as source_schema,
        *
    from raw_ficom_m3.t_rcall_avis_d
    where visit_date > '2026-03-01'
    {% if is_incremental() %}
      and visit_date > (select coalesce(max(visit_date), '1970-01-01') from {{ this }} where source_schema = 'm3')
    {% endif %}

),

unioned as (

    select * from source_m2
    union all
    select * from source_m3

)

select * from unioned