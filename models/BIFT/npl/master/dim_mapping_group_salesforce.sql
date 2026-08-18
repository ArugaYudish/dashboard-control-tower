{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_mapping_group_salesforce',
        indexes=[
          {'columns': ['salesforce_id'], 'type': 'btree'},
          {'columns': ['gsalesforce1_id'], 'type': 'btree'},
          {'columns': ['gsalesforce2_id'], 'type': 'btree'}
        ]
    )
}}

WITH m1 AS (
    SELECT DISTINCT ON (salesforce_id)
        'm1' AS source_schema,
        salesforce_id,
        salesforce_nm,
        NULL::text                              AS gsalesforce1_id,
        NULL::text                              AS gsalesforce1_nm,
        gsalesforce_id                          AS gsalesforce2_id,
        gsalesforce_nm                          AS gsalesforce2_nm,
        div_id,
        div_nm
    FROM raw_ficom_m1.m_mapping_group_salesforce
    WHERE salesforce_id IS NOT NULL
    ORDER BY salesforce_id, _airbyte_extracted_at DESC NULLS LAST
),

m2 AS (
    SELECT DISTINCT ON (salesforce_id)
        'm2' AS source_schema,
        salesforce_id,
        salesforce_nm,
        CASE
            WHEN salesforce_id::numeric IN (106, 120, 122, 219, 220) THEN 'Inti'
            ELSE 'Non Inti'
        END                                     AS gsalesforce1_id,
        CASE
            WHEN salesforce_id::numeric IN (106, 120, 122, 219, 220) THEN 'Inti'
            ELSE 'Non Inti'
        END                                     AS gsalesforce1_nm,
        gsalesforce_id                          AS gsalesforce2_id,
        gsalesforce_nm                          AS gsalesforce2_nm,
        div_id,
        div_nm
    FROM raw_ficom_m2.m_mapping_group_salesforce
    WHERE salesforce_id IS NOT NULL
    ORDER BY salesforce_id, _airbyte_extracted_at DESC NULLS LAST
),

m3 AS (
    SELECT DISTINCT ON (salesforce_id)
        'm3' AS source_schema,
        salesforce_id,
        salesforce_nm,
        NULL::text                              AS gsalesforce1_id,
        NULL::text                              AS gsalesforce1_nm,
        gsalesforce_id                          AS gsalesforce2_id,
        gsalesforce_nm                          AS gsalesforce2_nm,
        div_id,
        div_nm
    FROM raw_ficom_m3.m_mapping_group_salesforce
    WHERE salesforce_id IS NOT NULL
    ORDER BY salesforce_id, _airbyte_extracted_at DESC NULLS LAST
)

SELECT * FROM m1
UNION ALL
SELECT * FROM m2
UNION ALL
SELECT * FROM m3
