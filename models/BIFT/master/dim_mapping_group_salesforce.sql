{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_mapping_group_salesforce',
        indexes=[
          {'columns': ['source_schema', 'salesforce_id'], 'type': 'btree'},
          {'columns': ['salesforce_id'], 'type': 'btree'}
        ]
    )
}}

SELECT DISTINCT ON (source_schema, salesforce_id)
    salesforce_id,
    salesforce_nm,
    gsalesforce1_id,
    gsalesforce1_nm,
    gsalesforce2_id,
    gsalesforce2_nm,
    div_id,
    div_nm,
    source_schema
FROM (
    SELECT 
        salesforce_id, 
        salesforce_nm, 
        NULL::text AS gsalesforce1_id,
        NULL::text AS gsalesforce1_nm,
        gsalesforce_id AS gsalesforce2_id, 
        gsalesforce_nm AS gsalesforce2_nm, 
        div_id, 
        div_nm,
        'm1' AS source_schema
    FROM raw_ficom_m1.m_mapping_group_salesforce

    UNION ALL

    SELECT 
        salesforce_id, 
        salesforce_nm, 
        CASE 
            WHEN salesforce_id::numeric IN (106, 120, 122, 219, 220) THEN 'Inti'
            ELSE 'Non Inti'
        END AS gsalesforce1_id,
        CASE 
            WHEN salesforce_id::numeric IN (106, 120, 122, 219, 220) THEN 'Inti'
            ELSE 'Non Inti'
        END AS gsalesforce1_nm,
        gsalesforce_id AS gsalesforce2_id, 
        gsalesforce_nm AS gsalesforce2_nm, 
        div_id, 
        div_nm,
        'm2' AS source_schema
    FROM raw_ficom_m2.m_mapping_group_salesforce

    UNION ALL

    SELECT 
        salesforce_id, 
        salesforce_nm, 
        NULL::text AS gsalesforce1_id,
        NULL::text AS gsalesforce1_nm,
        gsalesforce_id AS gsalesforce2_id, 
        gsalesforce_nm AS gsalesforce2_nm, 
        div_id, 
        div_nm,
        'm3' AS source_schema
    FROM raw_ficom_m3.m_mapping_group_salesforce
) AS combined
ORDER BY source_schema, salesforce_id, div_id
