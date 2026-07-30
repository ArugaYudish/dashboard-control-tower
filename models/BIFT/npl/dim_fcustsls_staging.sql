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

SELECT 
    dfs.source_schema,
    dfs._airbyte_extracted_at,
    dfs.distributor_id,
    dfs.sls_id,
    dfs.cust_id,
    dfs.tahun,
    dfs.periode,
    dfs.channel_id,
    dfs.flag_aktif,
    dfs.group_outlet,
    dfs.salesforce_id,
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
    dc.cust_nm,
    loc.provinsi_code,
    loc.provinsi_name,
    loc.kabupaten_code,
    loc.kabupaten_name,
    loc.kecamatan_code,
    loc.kecamatan_name,
    loc.kelurahan_code,
    loc.kelurahan_name,
    dc.latitude,
    dc.longitude
FROM {{ ref('stg_fcustsls') }} dfs
LEFT JOIN bift.dim_customer dc 
    ON dc.distributor_id = dfs.distributor_id 
   AND dc.cust_id = dfs.cust_id 
LEFT JOIN bift.dim_lokasi loc
    ON dc.provinsi = loc.provinsi_code
   AND dc.kabupaten = loc.kabupaten_code
   AND dc.kecamatan = loc.kecamatan_code
   AND dc.kelurahan = loc.kelurahan_code
WHERE dfs.flag_aktif = 'Y' 
  AND dfs.salesforce_id NOT IN ('999', '116', '213', '222')
