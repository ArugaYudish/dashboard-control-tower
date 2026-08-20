{{ config(
    materialized='incremental',
    schema='bift',
    incremental_strategy='delete+insert',
    unique_key=[
        'source_schema',
        'distributor_id',
        'sls_id',
        'team_id',
        'salesforce_id',
        'outlet_id',
        'visit_date',
        'kode_ap'
    ]
) }}

with source_m2 as (

    select
        'm2'::text as source_schema,
        *
    from raw_ficom_m2.v_grading_banding
    where visit_date >= '2026-03-01'
    {% if is_incremental() %}
        -- Sinkron dengan window 14 hari view source
        and last_update >= CURRENT_DATE - INTERVAL '14 DAY'
    {% endif %}

),

source_m3 as (

    select
        'm3'::text as source_schema,
        *
    from raw_ficom_m3.v_grading_banding
    where visit_date >= '2026-03-01'
    {% if is_incremental() %}
        -- Sinkron dengan window 14 hari view source
        and last_update >= CURRENT_DATE - INTERVAL '14 DAY'
    {% endif %}

),

unioned as (

    select * from source_m2
    union all
    select * from source_m3

)

select * from unioned