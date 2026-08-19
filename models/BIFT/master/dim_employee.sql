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
        _airbyte_raw_id,
        _airbyte_extracted_at,
        _airbyte_meta,
        _airbyte_generation_id,
        nik,
        email,
        emp_id,
        emp_nm,
        user_id,
        upd_date,
        full_name,
        is_vacant,
        emp_type_id,
        superior_id,
        vacant_date,
        is_terminate,
        terminate_date
    FROM raw_ficom_m1.m_employee

    UNION ALL

    SELECT 
        'm2' AS source_schema,
        _airbyte_raw_id,
        _airbyte_extracted_at,
        _airbyte_meta,
        _airbyte_generation_id,
        nik,
        email,
        emp_id,
        emp_nm,
        user_id,
        upd_date,
        full_name,
        is_vacant,
        emp_type_id,
        superior_id,
        vacant_date,
        is_terminate,
        terminate_date
    FROM raw_ficom_m2.m_employee

    UNION ALL

    SELECT 
        'm3' AS source_schema,
        _airbyte_raw_id,
        _airbyte_extracted_at,
        _airbyte_meta,
        _airbyte_generation_id,
        nik,
        email,
        emp_id,
        emp_nm,
        user_id,
        upd_date,
        full_name,
        is_vacant,
        emp_type_id,
        superior_id,
        vacant_date,
        is_terminate,
        terminate_date
    FROM raw_ficom_m3.m_employee
)
SELECT DISTINCT ON (emp_id)
    source_schema,
    _airbyte_raw_id,
    _airbyte_extracted_at,
    _airbyte_meta,
    _airbyte_generation_id,
    nik,
    email,
    emp_id,
    emp_nm,
    user_id,
    upd_date,
    full_name,
    is_vacant,
    emp_type_id,
    superior_id,
    vacant_date,
    is_terminate,
    terminate_date
FROM combined_employee
WHERE emp_id IS NOT NULL
ORDER BY 
    emp_id, 
    upd_date DESC NULLS LAST,
    _airbyte_extracted_at DESC NULLS LAST