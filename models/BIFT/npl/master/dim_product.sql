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

SELECT
    dp.pcode,
    dp.pcode_nm,
    dp.div_id,
    dp.div_nm,
    dp.team_id,
    dp.team_nm,
    dp.class_team_id,
    dp.class_team_nm,
    dp.subbrand_id,
    dp.subbrand_nm,
    dp.gdiv_id,
    dp.gdiv_nm,
    dp.cat_id,
    dp.cat_nm,
    dp.sbu_id,
    dp.sbu_nm,
    dpp.convunit2,
    dpp.convunit3,
    dpp.unit1, 
    dpp.unit2,
    dpp.unit3 
FROM raw_olap_m3.dim_product dp
LEFT JOIN raw_olap_m3.dim_product_pack dpp 
       ON dp.pcode = dpp.pcode