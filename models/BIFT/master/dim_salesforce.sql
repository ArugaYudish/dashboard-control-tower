{{ config(
    materialized='table'
) }}

with source_m1 as (

    select
        'm1' as source_schema,
        salesforce_id,
        salesforce_nm
    from raw_ficom_m1.m_salesforce

),

source_m2 as (

    select
        'm2' as source_schema,
        salesforce_id,
        salesforce_nm
    from raw_ficom_m2.m_salesforce

),

source_m3 as (

    select
        'm3' as source_schema,
        salesforce_id,
        salesforce_nm
    from raw_ficom_m3.m_salesforce

),

unioned as (

    select * from source_m1
    union all
    select * from source_m2
    union all
    select * from source_m3

)

select * from unioned