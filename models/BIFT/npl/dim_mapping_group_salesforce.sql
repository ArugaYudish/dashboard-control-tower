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

WITH combined AS (
    SELECT
        'm1' AS source_schema,
        salesforce_id,
        salesforce_nm,
        NULL::text                              AS gsalesforce1_id,
        NULL::text                              AS gsalesforce1_nm,
        gsalesforce_id                          AS gsalesforce2_id,
        gsalesforce_nm                          AS gsalesforce2_nm,
        div_id,
        div_nm,
        _airbyte_extracted_at
    FROM raw_ficom_m1.m_mapping_group_salesforce

    UNION ALL

    SELECT
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
        div_nm,
        _airbyte_extracted_at
    FROM raw_ficom_m2.m_mapping_group_salesforce

    UNION ALL

    SELECT
        'm3' AS source_schema,
        salesforce_id,
        salesforce_nm,
        NULL::text                              AS gsalesforce1_id,
        NULL::text                              AS gsalesforce1_nm,
        gsalesforce_id                          AS gsalesforce2_id,
        gsalesforce_nm                          AS gsalesforce2_nm,
        div_id,
        div_nm,
        _airbyte_extracted_at
    FROM raw_ficom_m3.m_mapping_group_salesforce
)

SELECT DISTINCT ON (source_schema, salesforce_id)
    source_schema,

    -- Salesforce (break-by level 3)
    salesforce_id,
    salesforce_nm,

    -- Group Salesforce 1 — Inti / Non Inti (M2 only, NULL for M1 & M3)
    gsalesforce1_id,
    gsalesforce1_nm,

    -- Group Salesforce 2 — e.g. Modern Trade, Traditional Trade …
    gsalesforce2_id,
    gsalesforce2_nm,

    -- Division
    div_id,
    div_nm

FROM combined
WHERE salesforce_id IS NOT NULL
ORDER BY
    source_schema,
    salesforce_id,
    _airbyte_extracted_at DESC NULLS LAST
