{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_group_channel',
        indexes=[
          {'columns': ['channel_id'], 'type': 'btree'}
        ]
    )
}}

SELECT DISTINCT ON (channel_id) 
    *
FROM (
    SELECT DISTINCT ON (channel_id) 
        *
    FROM raw_ficom_m1.m_group_channels
    UNION ALL
    SELECT DISTINCT ON (channel_id) 
        *
    FROM raw_ficom_m2.m_group_channels
    UNION ALL
    SELECT DISTINCT ON (channel_id) 
        *
    FROM raw_ficom_m3.m_group_channels
    ORDER BY channel_id ASC
) AS a