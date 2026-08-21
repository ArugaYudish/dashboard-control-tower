{{
    config(
        schema='bift',
        materialized='incremental',
        alias='dim_customer',
        incremental_strategy='delete+insert',
        unique_key=['subdist_id', 'custno'],
        indexes=[
            {'columns': ['subdist_id', 'custno'], 'type': 'btree'}
        ]
    )
}}

select
    *
from raw_ho.v_fcustmst
where custno is not null 
  and subdist_id is not null
{% if is_incremental() %}
  -- Ambil data master customer yang di-update dalam 20 hari terakhir
  and clastupd >= CURRENT_DATE - INTERVAL '20 DAY'
{% endif %}