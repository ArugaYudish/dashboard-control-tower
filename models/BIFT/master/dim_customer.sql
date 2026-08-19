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
        mc.*,
        mvol.latitude,
        mvol.longitude
    FROM raw_ficom_m1.m_customer mc
    LEFT JOIN raw_ficom_m1.m_validasi_outlet_last mvol 
        ON mc.distributor_id = mvol.distributor_id 
       AND mc.cust_id = mvol.cust_id 

    UNION ALL

    SELECT 
        'm2' AS source_schema,
        mc.*,
        mvol.latitude,
        mvol.longitude
    FROM raw_ficom_m2.m_customer mc
    LEFT JOIN raw_ficom_m2.m_validasi_outlet_last mvol 
        ON mc.distributor_id = mvol.distributor_id 
       AND mc.cust_id = mvol.cust_id 

    UNION ALL

    SELECT 
        'm3' AS source_schema,
        mc.*,
        mvol.latitude,
        mvol.longitude
    FROM raw_ficom_m3.m_customer mc
    LEFT JOIN raw_ficom_m3.m_validasi_outlet_last mvol 
        ON mc.distributor_id = mvol.distributor_id 
       AND mc.cust_id = mvol.cust_id 
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