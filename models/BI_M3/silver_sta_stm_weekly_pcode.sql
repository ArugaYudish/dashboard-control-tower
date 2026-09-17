{{ config(
    materialized='table',
    indexes=[
      {'columns': ['year', 'week', 'distributor_id', 'pcode']}
    ]
) }}

-- 1. Cleansing & Normalisasi Data STM
with stm_raw as (
    select 
        case 
            when length(tahun::text) < 4 then week::int 
            else tahun::int 
        end as year,
        case 
            when length(tahun::text) < 4 then tahun::int 
            else week::int 
        end as week,
        distributor_id,
        pcode,
        omsetqty,
        omsetvalue
    from spx.v_omset_subdist_weekly_bw
),

-- 2. Cleansing & Normalisasi Data STA
sta_raw as (
    select 
        case 
            when length(year::text) < 4 then week::int 
            else year::int 
        end as year,
        case 
            when length(year::text) < 4 then year::int 
            else week::int 
        end as week,
        distributor_id,
        pcode,
        sta_qty,
        sta_value
    from spx.v_sta_subdist
),

-- 3. Agregasi STM
stm_summary as (
    select 
        year, 
        week, 
        distributor_id, 
        pcode,
        sum(omsetqty) as stm_qty,
        sum(omsetvalue) as stm_val
    from stm_raw
    group by 1, 2, 3, 4
),

-- 4. Agregasi STA
sta_summary as (
    select 
        year, 
        week, 
        distributor_id, 
        pcode,
        sum(sta_qty) as sta_qty,
        sum(sta_value) as sta_val
    from sta_raw
    group by 1, 2, 3, 4
),

-- 5. Menyiapkan Master Product Unik (Mencegah Duplikasi Row saat Join)
m_product_clean as (
    select distinct on (pcode)
        pcode,
        div_id,
        sls_div,      -- Dipanggil jika memang ada di m_product
        pcodename      -- Sesuaikan nama kolom deskripsi/nama produk (misal: pcode_nm / product_name)
    from spx.m_product
    order by pcode
)

-- 6. Final Join (Fakta STA/STM + Dimensi Product)
select 
    coalesce(sta.year, stm.year) as year,
    coalesce(sta.week, stm.week) as week,
    
    -- Format Week.Year tanpa leading zero (Contoh: 1.2025)
    coalesce(sta.week, stm.week)::text || '.' || coalesce(sta.year, stm.year)::text as week_year,
    
    coalesce(sta.distributor_id, stm.distributor_id) as distributor_id,
    coalesce(sta.pcode, stm.pcode) as pcode,
    
    -- Atribut dari m_product
    mp.pcodename as pcodename,
    mp.div_id,
    mp.sls_div,
    
    -- Metrik Qty dan Value
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
left join m_product_clean mp
    on coalesce(sta.pcode, stm.pcode) = mp.pcode