{{ config(
    materialized='table'
) }}

with raw_combined as (

    select * from raw_ficom_m1.m_salesforce
    union all
    select * from raw_ficom_m2.m_salesforce
    union all
    select * from raw_ficom_m3.m_salesforce

),

ranked_records as (

    select
        salesforce_id,
        salesforce_nm,
        row_number() over (
            partition by salesforce_id
            order by 
                case when nullif(trim(salesforce_nm), '') is not null then 1 else 2 end
        ) as rn
    from raw_combined

)

select
    salesforce_id,
    salesforce_nm
from ranked_records
where rn = 1