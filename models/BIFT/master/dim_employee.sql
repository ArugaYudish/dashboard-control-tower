{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_employee',
        indexes=[
          {'columns': ['emp_id'], 'type': 'btree'}
        ]
    )
}}

WITH combined_employee AS (
    SELECT 
        'm1' AS source_schema,
        *
    FROM raw_ficom_m1.m_employee

    UNION ALL

    SELECT 
        'm2' AS source_schema,
        *
    FROM raw_ficom_m2.m_employee

    UNION ALL

    SELECT 
        'm3' AS source_schema,
        *
    FROM raw_ficom_m3.m_employee
)
SELECT DISTINCT ON (emp_id)
    *
FROM combined_employee
WHERE emp_id IS NOT NULL
ORDER BY 
    emp_id, 
    _airbyte_extracted_at DESC NULLS LAST