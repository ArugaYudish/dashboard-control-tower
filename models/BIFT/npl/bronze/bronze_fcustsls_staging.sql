{{
    config(
        schema='bift',
        materialized='incremental',
        alias='bronze_fcustsls_staging',
        unique_key=['distributor_id', 'sls_id', 'cust_id', 'tahun', 'periode', 'source_schema'],
        incremental_strategy='delete_insert',
        pre_hook="""
            CREATE TABLE IF NOT EXISTS bift.bronze_fcustsls_staging (
                source_schema text NULL,
                _airbyte_extracted_at timestamptz NULL,
                distributor_id varchar NULL,
                sls_id varchar NULL,
                cust_id varchar NULL,
                tahun numeric NULL,
                periode numeric,
                channel_id varchar NULL,
                channel_nm varchar NULL,
                group_channel_id varchar NULL,
                group_channel_nm varchar NULL,
                flag_aktif varchar NULL,
                group_outlet varchar NULL,
                salesforce_id varchar NULL,
                gsalesforce1_id text NULL,
                gsalesforce1_nm text NULL,
                gsalesforce2_id varchar NULL,
                gsalesforce2_nm varchar NULL,
                salesforce_nm varchar NULL,
                team_id varchar NULL,
                hrabu varchar NULL,
                nobrs numeric NULL,
                route numeric NULL,
                hjumat varchar NULL,
                hkamis varchar NULL,
                hsabtu varchar NULL,
                hsenin varchar NULL,
                slimit numeric NULL,
                visit1 varchar NULL,
                visit2 varchar NULL,
                visit3 varchar NULL,
                visit4 varchar NULL,
                cycle_kunjungan text NULL,
                hminggu varchar NULL,
                hselasa varchar NULL,
                cust_nm varchar NULL,
                provinsi_code varchar NULL,
                provinsi_name varchar NULL,
                kabupaten_code varchar NULL,
                kabupaten_name varchar NULL,
                kecamatan_code varchar NULL,
                kecamatan_name varchar NULL,
                kelurahan_code varchar NULL,
                kelurahan_name varchar NULL,
                latitude varchar NULL,
                longitude varchar NULL
            ) PARTITION BY LIST (periode);

            DO $$
            DECLARE
                p INT;
            BEGIN
                FOR p IN 1..12 LOOP
                    EXECUTE format('CREATE TABLE IF NOT EXISTS bift.bronze_fcustsls_staging_p%s PARTITION OF bift.bronze_fcustsls_staging FOR VALUES IN (%s);', p, p);
                END LOOP;
                EXECUTE 'CREATE TABLE IF NOT EXISTS bift.bronze_fcustsls_staging_default PARTITION OF bift.bronze_fcustsls_staging DEFAULT;';
            END $$;
        """,
        indexes=[
          {'columns': ['periode', 'tahun', 'distributor_id'], 'type': 'btree'},
          {'columns': ['distributor_id', 'sls_id', 'cust_id'], 'type': 'btree'}
        ]
    )
}}

WITH customer_with_location AS (
    SELECT DISTINCT ON (dc.distributor_id, dc.cust_id)
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
    ORDER BY dc.distributor_id, dc.cust_id
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
FROM {{ ref('dim_fcustsls') }} dfs
LEFT JOIN {{ ref('stg_mapping_group_salesforce') }} mmgs
    ON dfs.salesforce_id = mmgs.salesforce_id
   AND dfs.source_schema = mmgs.source_schema
LEFT JOIN customer_with_location cwl
    ON dfs.distributor_id = cwl.distributor_id 
   AND dfs.cust_id = cwl.cust_id
WHERE dfs.channel_id != '999'
{% if is_incremental() and var('periode', none) is not none %}
  AND dfs.periode = {{ var('periode') }}
{% endif %}
{% if is_incremental() and var('tahun', none) is not none %}
  AND dfs.tahun = {{ var('tahun') }}
{% endif %}

