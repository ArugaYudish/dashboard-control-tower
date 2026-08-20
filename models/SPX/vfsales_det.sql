{{
  config(
    materialized='incremental',
    schema='spx',
    pre_hook=[
      "{% if is_incremental() %}
         DELETE FROM spx.vfsales_det 
         WHERE inv_date >= '2026-07-23 00:00:00.000';
       {% endif %}"
    ]
  )
}}

select
    *
from raw_ho.vfsales_det

{% if is_incremental() %}
    where inv_date >= '2026-07-23 00:00:00.000'
{% endif %}