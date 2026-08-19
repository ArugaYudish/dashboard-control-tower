{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_distributor',
        indexes=[
          {'columns': ['distributor_id'], 'type': 'btree'}
        ]
    )
}}

WITH combined_distributor AS (
    SELECT 
        'm1' AS source_schema,
        *
    FROM raw_ficom_m1.m_distributor

    UNION ALL

    SELECT 
        'm2' AS source_schema,
        *
    FROM raw_ficom_m2.m_distributor

    UNION ALL

    SELECT 
        'm3' AS source_schema,
        *
    FROM raw_ficom_m3.m_distributor
)
SELECT DISTINCT ON (distributor_id)
    *
FROM combined_distributor
WHERE distributor_id IS NOT NULL
ORDER BY 
    distributor_id, 
    _airbyte_extracted_at DESC NULLS LAST
