{{ config(
    materialized='table',
    indexes=[
      {'columns': ['year', 'week', 'distributor_id', 'pcode']}
    ]
) }}

with stm_summary as (
    select 
        cast(tahun as int) as year,
        cast(week as int) as week,
        distributor_id,
        pcode,
        sum(omsetqty) as stm_qty,
        sum(omsetvalue) as stm_val
    from spx.v_omset_subdist_weekly_bw
    group by 1, 2, 3, 4
),

sta_summary as (
    select 
        cast(year as int) as year,    -- Mengambil kolom 'year' asli
        cast(week as int) as week,    -- Mengambil kolom 'week' asli
        distributor_id,
        pcode,
        sum(sta_qty) as sta_qty,
        sum(sta_value) as sta_val
    from spx.v_sta_subdist
    group by 1, 2, 3, 4
)

select 
    coalesce(sta.year, stm.year) as year,
    coalesce(sta.week, stm.week) as week,
    
    -- FORMAT LENGKAP: Week (2 digit) . Year (4 digit) -> Hasil: 30.2025
    lpad(coalesce(sta.week, stm.week)::text, 2, '0') || '.' || coalesce(sta.year, stm.year)::text as week_year,
    
    coalesce(sta.distributor_id, stm.distributor_id) as distributor_id,
    coalesce(sta.pcode, stm.pcode) as pcode,
    
    coalesce(sta.sta_qty, 0) as sta_qty,
    coalesce(stm.stm_qty, 0) as stm_qty,
    coalesce(sta.sta_val, 0) as sta_val,
    coalesce(stm.stm_val, 0) as stm_val,
    
    now() as loaded_at

from sta_summary sta
full outer join stm_summary stm 
    on  sta.year           = stm.year 
    and sta.week           = stm.week 
    and sta.distributor_id = stm.distributor_id 
    and sta.pcode          = stm.pcode