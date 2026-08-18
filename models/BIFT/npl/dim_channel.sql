{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_channel',
        indexes=[
          {'columns': ['channel_id'], 'type': 'btree'}
        ]
    )
}}

WITH combined_channel AS (
    SELECT 
        'm1' AS source_schema,
        *
    FROM raw_ficom_m1.m_channel

    UNION ALL

    SELECT 
        'm2' AS source_schema,
        *
    FROM raw_ficom_m2.m_channel

    UNION ALL

    SELECT 
        'm3' AS source_schema,
        *
    FROM raw_ficom_m3.m_channel
)
SELECT DISTINCT ON (channel_id)
    *
FROM combined_channel
WHERE channel_id IS NOT NULL
ORDER BY 
    channel_id, 
    _airbyte_extracted_at DESC NULLS LAST