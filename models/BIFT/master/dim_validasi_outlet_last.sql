{{
    config(
        schema='bift',
        materialized='incremental',
        alias='dim_validasi_outlet_last',
        unique_key=['distributor_id', 'cust_id'],
        incremental_strategy='delete+insert',
        indexes=[
          {'columns': ['distributor_id', 'cust_id'], 'type': 'btree'}
        ]
    )
}}

WITH combined_validasi_outlet AS (
    SELECT 
        'm1' AS source_schema,
        distributor_id,
        cust_id,
        latitude,
        longitude,
        _airbyte_extracted_at
    FROM raw_ficom_m1.m_validasi_outlet_last
    {% if is_incremental() %}
    WHERE _airbyte_extracted_at > (SELECT COALESCE(MAX(_airbyte_extracted_at), '1970-01-01'::timestamptz) FROM {{ this }})
    {% endif %}

    UNION ALL

    SELECT 
        'm2' AS source_schema,
        distributor_id,
        cust_id,
        latitude,
        longitude,
        _airbyte_extracted_at
    FROM raw_ficom_m2.m_validasi_outlet_last
    {% if is_incremental() %}
    WHERE _airbyte_extracted_at > (SELECT COALESCE(MAX(_airbyte_extracted_at), '1970-01-01'::timestamptz) FROM {{ this }})
    {% endif %}

    UNION ALL

    SELECT 
        'm3' AS source_schema,
        distributor_id,
        cust_id,
        latitude,
        longitude,
        _airbyte_extracted_at
    FROM raw_ficom_m3.m_validasi_outlet_last
    {% if is_incremental() %}
    WHERE _airbyte_extracted_at > (SELECT COALESCE(MAX(_airbyte_extracted_at), '1970-01-01'::timestamptz) FROM {{ this }})
    {% endif %}
)

SELECT DISTINCT ON (distributor_id, cust_id)
    source_schema,
    distributor_id,
    cust_id,
    latitude,
    longitude,
    _airbyte_extracted_at
FROM combined_validasi_outlet
WHERE distributor_id IS NOT NULL 
  AND cust_id IS NOT NULL
ORDER BY 
    distributor_id, 
    cust_id, 
    _airbyte_extracted_at DESC NULLS LAST