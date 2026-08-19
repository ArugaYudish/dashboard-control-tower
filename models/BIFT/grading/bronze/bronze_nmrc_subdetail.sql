{{ config(
    materialized='incremental',
    unique_key=[
        'source_schema',
        'distributor_id',
        'spv_id',
        'sls_id',
        'week',
        'tgl',
        'tahun',
        'periode'
    ]
) }}

with source_m2 as (

    select
        'm2' as source_schema,
        *
    from raw_ficom_m2.v_nmrc_subdetail
    where tgl > '2026-03-01'
    {% if is_incremental() %}
      and upd_date > (select coalesce(max(upd_date), '1970-01-01') from {{ this }} where source_schema = 'm2')
    {% endif %}

),

source_m3 as (

    select
        'm3' as source_schema,
        *
    from raw_ficom_m3.v_nmrc_subdetail
    where tgl > '2026-03-01'
    {% if is_incremental() %}
      and upd_date > (select coalesce(max(upd_date), '1970-01-01') from {{ this }} where source_schema = 'm3')
    {% endif %}

),

unioned as (

    select * from source_m2
    union all
    select * from source_m3

)

select * from unioned