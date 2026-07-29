{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_fcustsls_staging',
        pre_hook=[
            "set local work_mem = '512MB'",
            "set local maintenance_work_mem = '1GB'"
        ],
        indexes=[
          {'columns': ['distributor_id', 'sls_id', 'cust_id', 'tahun', 'periode'], 'type': 'btree'},
          {'columns': ['distributor_id', 'sls_id'], 'type': 'btree'},
          {'columns': ['distributor_id', 'cust_id'], 'type': 'btree'}
        ]
    )
}}

WITH group_channel_staging AS (
    SELECT DISTINCT ON (channel_id) 
        *
    FROM (
        SELECT DISTINCT ON (channel_id) 
            channel_id,
            channel_nm,
            group_channel_id,
            group_channel_nm
        FROM raw_ficom_m1.m_group_channels
        UNION ALL
        SELECT DISTINCT ON (channel_id) 
            channel_id,
            channel_nm,
            group_channel_id,
            group_channel_nm
        FROM raw_ficom_m2.m_group_channels
        UNION ALL
        SELECT DISTINCT ON (channel_id) 
            channel_id,
            channel_nm,
            group_channel_id,
            group_channel_nm
        FROM raw_ficom_m3.m_group_channels
        ORDER BY channel_id ASC
    ) AS a
),
combined_staging AS (
    SELECT 
        'm1' AS source_schema,
        *
    FROM raw_ficom_m1.v_fcustsls_staging
    UNION ALL
    SELECT 
        'm2' AS source_schema,
        *
    FROM raw_ficom_m2.v_fcustsls_staging
    UNION ALL
    SELECT 
        'm3' AS source_schema,
        *
    FROM raw_ficom_m3.v_fcustsls_staging
),

latest_staging_per_period AS (
    SELECT DISTINCT ON (distributor_id, sls_id, cust_id, tahun, periode)
        *
    FROM combined_staging
    WHERE cust_id IS NOT NULL
      AND distributor_id IS NOT NULL
      AND tahun IS NOT NULL
      AND periode IS NOT NULL
    ORDER BY 
        distributor_id,
        sls_id,
        cust_id,
        tahun,
        periode,
        upd_date DESC NULLS LAST,
        _airbyte_extracted_at DESC NULLS LAST
)

SELECT 
    l.*,
    CASE 
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'YYYY' THEN 'Weekly'
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'YTYT' THEN 'BiWeekly1'
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'TYTY' THEN 'BiWeekly2'
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'YTTT' THEN 'Monthly1'
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'TYTT' THEN 'Monthly2'
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'TTYT' THEN 'Monthly3'
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'TTTY' THEN 'Monthly4'
    END AS cycle_kunjungan,
    gc.channel_nm,
    gc.group_channel_id,
    gc.group_channel_nm,
    dc.cust_nm,
    dc.address || dc.address2 AS address,
    dc.provinsi,
    dl.provinsi_name,
    dc.kabupaten,
    dl.kabupaten_name,
    dc.kecamatan,
    dl.kecamatan_name,
    dc.kelurahan,
    dl.kelurahan_name,
    dc.contact_person
FROM latest_staging_per_period l
LEFT JOIN group_channel_staging gc
       ON l.channel_id = gc.channel_id
LEFT JOIN bift.dim_customer dc
       ON dc.distributor_id = l.distributor_id
      AND dc.cust_id        = l.cust_id
LEFT JOIN bift.dim_lokasi dl
       ON dl.kelurahan_code = dc.kelurahan