{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_group_channel',
        indexes=[
          {'columns': ['source_schema', 'channel_id'], 'type': 'btree'},
          {'columns': ['channel_id'], 'type': 'btree'}
        ]
    )
}}

SELECT DISTINCT ON (source_schema, channel_id) 
    *
FROM (
    (
        SELECT DISTINCT ON (channel_id) 
            'm1' AS source_schema,
            *
        FROM raw_ficom_m1.m_group_channels
        ORDER BY channel_id ASC
    )
    UNION ALL
    (
        SELECT DISTINCT ON (channel_id) 
            'm2' AS source_schema,
            *
        FROM raw_ficom_m2.m_group_channels
        ORDER BY channel_id ASC
    )
    UNION ALL
    (
        SELECT DISTINCT ON (channel_id) 
            'm3' AS source_schema,
            *
        FROM raw_ficom_m3.m_group_channels
        ORDER BY channel_id ASC
    )
) AS a
ORDER BY source_schema, channel_id ASC