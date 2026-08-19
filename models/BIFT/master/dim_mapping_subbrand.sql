{{ config(
    materialized='table'
) }}

with raw_combined as (

    select * from raw_ficom_m1.m_mapping_subbrand
    union all
    select * from raw_ficom_m2.m_mapping_subbrand
    union all
    select * from raw_ficom_m3.m_mapping_subbrand

),

ranked_records as (

    select
        *,
        row_number() over (
            partition by 
                div_id, 
                team_id, 
                class_team_id, 
                subbrand_id
            order by 
                -- Prioritaskan record yang cat_id & cat_nm tidak null/kosong
                case when nullif(trim(cat_id), '') is not null then 1 else 2 end,
                case when nullif(trim(cat_nm), '') is not null then 1 else 2 end
        ) as rn
    from raw_combined

)

select * exclude (rn)
from ranked_records
where rn = 1