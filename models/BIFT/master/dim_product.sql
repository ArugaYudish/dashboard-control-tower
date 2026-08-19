{{ config(
    materialized='table'
) }}

with raw_combined as (

    select * from raw_ficom_m1.m_product
    union all
    select * from raw_ficom_m2.m_product
    union all
    select * from raw_ficom_m3.m_product

),

ranked_records as (

    select
        *,
        row_number() over (
            partition by pcode
            order by 
                case when nullif(trim(pcode_nm), '') is not null then 1 else 2 end,
                case when coalesce(sell_price1, 0) > 0 then 1 else 2 end
        ) as rn
    from raw_combined

)

select * exclude (rn)
from ranked_records
where rn = 1