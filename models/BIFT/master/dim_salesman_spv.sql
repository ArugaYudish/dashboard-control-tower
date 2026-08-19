{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_salesman_spv',
        indexes=[
          {'columns': ['distributor_id', 'sls_id'], 'type': 'btree'},
          {'columns': ['spv_id'], 'type': 'btree'},
          {'columns': ['source_schema'], 'type': 'btree'}
        ]
    )
}}

WITH m1 AS (
    SELECT DISTINCT ON (distributor_id, sls_id)
        'm1' AS source_schema,
        distributor_id,
        sls_id,
        spv_id,
        upd_date,
        _airbyte_extracted_at
    FROM raw_ficom_m1.m_salesman_spv
    WHERE distributor_id IS NOT NULL 
      AND sls_id IS NOT NULL
    ORDER BY 
        distributor_id, 
        sls_id, 
        upd_date DESC NULLS LAST,
        _airbyte_extracted_at DESC NULLS LAST
),

m2 AS (
    SELECT DISTINCT ON (distributor_id, sls_id)
        'm2' AS source_schema,
        distributor_id,
        sls_id,
        spv_id,
        upd_date,
        _airbyte_extracted_at
    FROM raw_ficom_m2.m_salesman_spv
    WHERE distributor_id IS NOT NULL 
      AND sls_id IS NOT NULL
    ORDER BY 
        distributor_id, 
        sls_id, 
        upd_date DESC NULLS LAST,
        _airbyte_extracted_at DESC NULLS LAST
),

m3 AS (
    SELECT DISTINCT ON (distributor_id, sls_id)
        'm3' AS source_schema,
        distributor_id,
        sls_id,
        spv_id,
        upd_date,
        _airbyte_extracted_at
    FROM raw_ficom_m3.m_salesman_spv
    WHERE distributor_id IS NOT NULL 
      AND sls_id IS NOT NULL
    ORDER BY 
        distributor_id, 
        sls_id, 
        upd_date DESC NULLS LAST,
        _airbyte_extracted_at DESC NULLS LAST
)

SELECT * FROM m1
UNION ALL
SELECT * FROM m2
UNION ALL
SELECT * FROM m3

