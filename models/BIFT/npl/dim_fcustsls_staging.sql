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

WITH customer_with_location AS (
    SELECT 
        dc.distributor_id,
        dc.cust_id,
        dc.cust_nm,
        dc.latitude,
        dc.longitude,
        loc.provinsi_code,
        loc.provinsi_name,
        loc.kabupaten_code,
        loc.kabupaten_name,
        loc.kecamatan_code,
        loc.kecamatan_name,
        loc.kelurahan_code,
        loc.kelurahan_name
    FROM bift.dim_customer dc
    LEFT JOIN bift.dim_lokasi loc
        ON dc.provinsi = loc.provinsi_code
       AND dc.kabupaten = loc.kabupaten_code
       AND dc.kecamatan = loc.kecamatan_code
       AND dc.kelurahan = loc.kelurahan_code
)

SELECT 
    dfs.source_schema,
    dfs._airbyte_extracted_at,
    dfs.distributor_id,
    dfs.sls_id,
    dfs.cust_id,
    dfs.tahun,
    dfs.periode,
    dfs.channel_id,
    dfs.channel_nm,
    dfs.group_channel_id,
    dfs.group_channel_nm,
    dfs.flag_aktif,
    dfs.group_outlet,
    dfs.salesforce_id,
    mmgs.gsalesforce1_id,
    mmgs.gsalesforce1_nm,
    mmgs.gsalesforce2_id,
    mmgs.gsalesforce2_nm,
    mmgs.salesforce_nm,
    dfs.team_id,
    dfs.hrabu,
    dfs.nobrs,
    dfs.route,
    dfs.hjumat,
    dfs.hkamis,
    dfs.hsabtu,
    dfs.hsenin,
    dfs.slimit,
    dfs.visit1,
    dfs.visit2,
    dfs.visit3,
    dfs.visit4,
    dfs.cycle_kunjungan,
    dfs.hminggu,
    dfs.hselasa,

    -- Customer & Location Details
    cwl.cust_nm,
    cwl.provinsi_code,
    cwl.provinsi_name,
    cwl.kabupaten_code,
    cwl.kabupaten_name,
    cwl.kecamatan_code,
    cwl.kecamatan_name,
    cwl.kelurahan_code,
    cwl.kelurahan_name,
    cwl.latitude,
    cwl.longitude
FROM {{ ref('stg_fcustsls') }} dfs
LEFT JOIN {{ ref('stg_mapping_group_salesforce') }} mmgs
    ON dfs.salesforce_id = mmgs.salesforce_id
   AND dfs.source_schema = mmgs.source_schema
LEFT JOIN customer_with_location cwl
    ON dfs.distributor_id = cwl.distributor_id 
   AND dfs.cust_id = cwl.cust_id

