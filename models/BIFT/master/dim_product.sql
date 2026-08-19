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
        pcode,
        pcode_nm,
        prlin,
        brand,
        sbra1,
        sbra2,
        unit1,
        unit2,
        unit3,
        conv_unit2,
        conv_unit3,
        sell_price1,
        sell_price2,
        sell_price3,
        is_focus,
        pc_parent,
        is_competitor,
        row_number() over (
            partition by pcode
            order by 
                case when nullif(trim(pcode_nm), '') is not null then 1 else 2 end,
                case when coalesce(sell_price1, 0) > 0 then 1 else 2 end
        ) as rn
    from raw_combined

)

select
    pcode,
    pcode_nm,
    prlin,
    brand,
    sbra1,
    sbra2,
    unit1,
    unit2,
    unit3,
    conv_unit2,
    conv_unit3,
    sell_price1,
    sell_price2,
    sell_price3,
    is_focus,
    pc_parent,
    is_competitor
from ranked_records
where rn = 1