{{ config(
    materialized='table'
) }}

with raw_combined as (

    select
        'm1' as source_schema,
        _airbyte_raw_id,
        _airbyte_extracted_at,
        _airbyte_meta,
        _airbyte_generation_id,
        brand,
        pcode,
        prlin,
        sbra1,
        sbra2,
        unit1,
        unit2,
        unit3,
        is_focus,
        pcode_nm,
        pc_parent,
        conv_unit2,
        conv_unit3,
        sell_price1,
        sell_price2,
        sell_price3
    from raw_ficom_m1.m_product

    union all

    select
        'm2' as source_schema,
        _airbyte_raw_id,
        _airbyte_extracted_at,
        _airbyte_meta,
        _airbyte_generation_id,
        brand,
        pcode,
        prlin,
        sbra1,
        sbra2,
        unit1,
        unit2,
        unit3,
        is_focus,
        pcode_nm,
        pc_parent,
        conv_unit2,
        conv_unit3,
        sell_price1,
        sell_price2,
        sell_price3
    from raw_ficom_m2.m_product

    union all

    select
        'm3' as source_schema,
        _airbyte_raw_id,
        _airbyte_extracted_at,
        _airbyte_meta,
        _airbyte_generation_id,
        brand,
        pcode,
        prlin,
        sbra1,
        sbra2,
        unit1,
        unit2,
        unit3,
        is_focus,
        pcode_nm,
        pc_parent,
        conv_unit2,
        conv_unit3,
        sell_price1,
        sell_price2,
        sell_price3
    from raw_ficom_m3.m_product

),

ranked_records as (

    select
        source_schema,
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
        _airbyte_extracted_at,
        row_number() over (
            partition by pcode
            order by 
                case when nullif(trim(pcode_nm), '') is not null then 1 else 2 end,
                case when coalesce(sell_price1, 0) > 0 then 1 else 2 end,
                _airbyte_extracted_at desc nulls last
        ) as rn
    from raw_combined

)

select
    source_schema,
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
    pc_parent
from ranked_records
where rn = 1