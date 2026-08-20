{{
  config(
    materialized='incremental',
    schema='spx',
    pre_hook=[
      "{% if is_incremental() %}
         DELETE FROM spx.vfsales_det 
         WHERE inv_date >= CURRENT_DATE - INTERVAL '10 DAY';
       {% endif %}"
    ]
  )
}}

select
    *
from raw_ho.vfsales_det

{% if is_incremental() %}
    where inv_date >= CURRENT_DATE - INTERVAL '10 DAY'
{% endif %}