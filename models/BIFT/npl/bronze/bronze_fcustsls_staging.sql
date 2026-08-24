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
    SELECT DISTINCT ON (f.subdist_id, f.custno)
        f.subdist_id AS distributor_id,
        f.custno AS cust_id,
        f.custname AS cust_nm,
        vol.latitude,
        vol.longitude,
        dl.provinsi_code,
        dl.provinsi_name,
        dl.kabupaten_code,
        dl.kabupaten_name,
        dl.kecamatan_code,
        dl.kecamatan_name,
        dl.kelurahan_code,
        dl.kelurahan_name
    FROM bift.dim_customer f
    LEFT JOIN bift.dim_lokasi dl
        ON f.prop_id = dl.provinsi_code 
       AND f.kab_id = dl.kabupaten_code 
       AND f.kec_id = dl.kecamatan_code 
       AND f.kel_id = dl.kelurahan_code 
    LEFT JOIN bift.dim_validasi_outlet_last vol
        ON f.subdist_id = vol.distributor_id
       AND f.custno = vol.cust_id
    ORDER BY f.subdist_id, f.custno
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
{% if is_incremental() %}
  {% if var('periode', none) is not none and var('tahun', none) is not none %}
    {# Manual backfill: dbt run --vars '{"periode": 8, "tahun": 2026}' #}
    AND dfs.periode = {{ var('periode') }}
    AND dfs.tahun = {{ var('tahun') }}
  {% else %}
    {# Auto-detect: cek langsung dari raw tables, skip ephemeral yang berat #}
    AND (dfs.source_schema, dfs.tahun, dfs.periode) IN (
        SELECT DISTINCT source_schema, tahun, periode
        FROM (
            SELECT 'm1' AS source_schema, tahun, periode, _airbyte_extracted_at FROM raw_ficom_m1.v_fcustsls_staging
            UNION ALL
            SELECT 'm2' AS source_schema, tahun, periode, _airbyte_extracted_at FROM raw_ficom_m2.v_fcustsls_staging
            UNION ALL
            SELECT 'm3' AS source_schema, tahun, periode, _airbyte_extracted_at FROM raw_ficom_m3.v_fcustsls_staging
        ) raw_check
        WHERE _airbyte_extracted_at > (
            SELECT COALESCE(MAX(_airbyte_extracted_at), '1970-01-01'::timestamptz)
            FROM {{ this }}
        )
    )
  {% endif %}
{% endif %}
