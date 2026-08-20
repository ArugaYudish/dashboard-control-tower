{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_product',
        indexes=[
          {'columns': ['pcode'], 'type': 'btree'}
        ]
    )
}}

with product as (

    select
        pcode,
        pcodename as pcode_nm,
        prlin,
        brand,
        sbra1,
        convunit2 as conv_unit2,
        convunit3 as conv_unit3,
        unit1,
        unit2,
        unit3,
        sellprice1 as sell_price1,
        sellprice2 as sell_price2,
        sellprice3 as sell_price3,
        _airbyte_extracted_at
    from raw_ho.fmaster

),

mapping_subbrand as (

    select * from {{ ref('dim_mapping_subbrand') }}

),

product_snopix as (

    select * from spx.m_product

),

division as (

    select * from {{ ref('dim_division') }}

),

joined as (

    select
        p.pcode,
        p.pcode_nm,
        ms.div_id,
        ms.div_nm,
        ms.team_id,
        ms.team_nm,
        ms.class_team_id,
        ms.class_team_nm,
        ms.subbrand_id,
        ms.subbrand_nm,
        ms.gdiv_id,
        ms.gdiv_nm,
        ms.cat_id,
        ms.cat_nm,
        sp.div_id as sbu_id,
        sd.div_nm as sbu_nm,
        cast(null as varchar(50)) as mapping_bift,
        cast(null as varchar(50)) as mapping_bift_nm,
        p.conv_unit2,
        p.conv_unit3,
        p.unit1,
        p.unit2,
        p.unit3,
        p.sell_price1,
        p.sell_price2,
        p.sell_price3,
        p._airbyte_extracted_at

    from product p
    left join mapping_subbrand ms 
      on (coalesce(p.prlin, '') || coalesce(p.brand, '') || coalesce(p.sbra1, '')) = ms.subbrand_id
    left join product_snopix sp 
      on sp.pcode = p.pcode
    left join division sd 
      on sd.div_id = sp.div_id

),

deduplicated as (

    select
        cast(pcode as varchar(100)) as pcode,
        cast(pcode_nm as varchar(100)) as pcode_nm,
        cast(div_id as varchar(100)) as div_id,
        cast(div_nm as varchar(100)) as div_nm,
        cast(team_id as varchar(100)) as team_id,
        cast(team_nm as varchar(100)) as team_nm,
        cast(class_team_id as varchar(100)) as class_team_id,
        cast(class_team_nm as varchar(100)) as class_team_nm,
        cast(subbrand_id as varchar(100)) as subbrand_id,
        cast(subbrand_nm as varchar(100)) as subbrand_nm,
        cast(gdiv_id as varchar(100)) as gdiv_id,
        cast(gdiv_nm as varchar(100)) as gdiv_nm,
        cast(cat_id as varchar(100)) as cat_id,
        cast(cat_nm as varchar(100)) as cat_nm,
        cast(sbu_id as varchar) as sbu_id,
        cast(sbu_nm as varchar) as sbu_nm,
        cast(mapping_bift as varchar(50)) as mapping_bift,
        cast(mapping_bift_nm as varchar(50)) as mapping_bift_nm,
        conv_unit2,
        conv_unit3,
        unit1,
        unit2,
        unit3,
        sell_price1,
        sell_price2,
        sell_price3,
        row_number() over (
            partition by pcode
            order by _airbyte_extracted_at desc
        ) as rn

    from joined

),

final as (

    select
        pcode,
        pcode_nm,
        div_id,
        div_nm,
        team_id,
        team_nm,
        class_team_id,
        class_team_nm,
        subbrand_id,
        subbrand_nm,
        gdiv_id,
        gdiv_nm,
        cat_id,
        cat_nm,
        sbu_id,
        sbu_nm,
        mapping_bift,
        mapping_bift_nm,
        conv_unit2,
        conv_unit3,
        unit1,
        unit2,
        unit3,
        sell_price1,
        sell_price2,
        sell_price3

    from deduplicated
    where rn = 1

)

select * from final