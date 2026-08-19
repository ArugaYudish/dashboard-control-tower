{{ config(
    materialized='table'
) }}

with raw_combined as (

    select * from raw_ficom_m1.m_team
    union all
    select * from raw_ficom_m2.m_team
    union all
    select * from raw_ficom_m3.m_team

),

ranked_records as (

    select
        *,
        row_number() over (
            partition by team_id
            order by 
                case when nullif(trim(team_nm), '') is not null then 1 else 2 end
        ) as rn
    from raw_combined

)

select * exclude (rn)
from ranked_records
where rn = 1