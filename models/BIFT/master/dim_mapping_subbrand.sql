{{ config(
    schema='bift',
    materialized='table'
) }}

with raw_combined as (

    select
        'm1' as source_schema,
        _airbyte_raw_id,
        _airbyte_extracted_at,
        _airbyte_meta,
        _airbyte_generation_id,
        cat_id,
        cat_nm,
        div_id,
        div_nm,
        gdiv_id,
        gdiv_nm,
        team_id,
        team_nm,
        subbrand_id,
        subbrand_nm,
        class_team_id,
        class_team_nm
    from raw_ficom_m1.m_mapping_subbrand

    union all

    select
        'm2' as source_schema,
        _airbyte_raw_id,
        _airbyte_extracted_at,
        _airbyte_meta,
        _airbyte_generation_id,
        cat_id,
        cat_nm,
        div_id,
        div_nm,
        gdiv_id,
        gdiv_nm,
        team_id,
        team_nm,
        subbrand_id,
        subbrand_nm,
        class_team_id,
        class_team_nm
    from raw_ficom_m2.m_mapping_subbrand

    union all

    select
        'm3' as source_schema,
        _airbyte_raw_id,
        _airbyte_extracted_at,
        _airbyte_meta,
        _airbyte_generation_id,
        cat_id,
        cat_nm,
        div_id,
        div_nm,
        gdiv_id,
        gdiv_nm,
        team_id,
        team_nm,
        subbrand_id,
        subbrand_nm,
        class_team_id,
        class_team_nm
    from raw_ficom_m3.m_mapping_subbrand

),

ranked_records as (

    select
        source_schema,
        _airbyte_raw_id,
        _airbyte_extracted_at,
        _airbyte_meta,
        _airbyte_generation_id,
        cat_id,
        cat_nm,
        div_id,
        div_nm,
        gdiv_id,
        gdiv_nm,
        team_id,
        team_nm,
        subbrand_id,
        subbrand_nm,
        class_team_id,
        class_team_nm,
        row_number() over (
            partition by 
                div_id, 
                team_id, 
                class_team_id, 
                subbrand_id
            order by 
                case when nullif(trim(cat_id), '') is not null then 1 else 2 end,
                case when nullif(trim(cat_nm), '') is not null then 1 else 2 end,
                _airbyte_extracted_at desc nulls last
        ) as rn
    from raw_combined

)

select
    source_schema,
    _airbyte_raw_id,
    _airbyte_extracted_at,
    _airbyte_meta,
    _airbyte_generation_id,
    cat_id,
    cat_nm,
    div_id,
    div_nm,
    gdiv_id,
    gdiv_nm,
    team_id,
    team_nm,
    subbrand_id,
    subbrand_nm,
    class_team_id,
    class_team_nm
from ranked_records
where rn = 1