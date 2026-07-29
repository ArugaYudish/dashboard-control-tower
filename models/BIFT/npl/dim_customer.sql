{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_customer',
        indexes=[
          {'columns': ['distributor_id', 'cust_id'], 'type': 'btree'}
        ]
    )
}}

WITH combined_customer AS (
    SELECT 
        'm1' AS source_schema,
        *
    FROM raw_ficom_m1.m_customer

    UNION ALL

    SELECT 
        'm2' AS source_schema,
        *
    FROM raw_ficom_m2.m_customer

    UNION ALL

    SELECT 
        'm3' AS source_schema,
        *
    FROM raw_ficom_m3.m_customer
)
SELECT DISTINCT ON (distributor_id, cust_id)
    *
FROM combined_customer
WHERE cust_id IS NOT NULL 
  AND distributor_id IS NOT NULL
ORDER BY 
    distributor_id, 
    cust_id, 
    _airbyte_extracted_at DESC NULLS LAST