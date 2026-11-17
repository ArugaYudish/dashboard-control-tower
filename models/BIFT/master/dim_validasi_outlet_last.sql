{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_validasi_outlet_last',
        pre_hook=[
            "SET LOCAL work_mem = '256MB'"
        ],
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

    UNION ALL

    SELECT 
        'm2' AS source_schema,
        distributor_id,
        cust_id,
        latitude,
        longitude,
        _airbyte_extracted_at
    FROM raw_ficom_m2.m_validasi_outlet_last

    UNION ALL

    SELECT 
        'm3' AS source_schema,
        distributor_id,
        cust_id,
        latitude,
        longitude,
        _airbyte_extracted_at
    FROM raw_ficom_m3.m_validasi_outlet_last
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