{{
    config(
        schema='bift',
        materialized='incremental',
        alias='bronze_cb',
        unique_key=['distributor_id', 'ss_id', 'sls_id', 'cust_id', 'tahun', 'periode'],
        incremental_strategy='delete+insert',
        pre_hook="""
            CREATE TABLE IF NOT EXISTS bift.bronze_cb (
                source_schema text NULL,
                _airbyte_extracted_at timestamptz NULL,
                updated_at timestamptz NULL,
                tahun numeric NULL,
                periode numeric NULL,
                tahun_periode numeric NULL,
                gdiv_id text NULL,
                gdiv_nm text NULL,
                sd_id varchar NULL,
                sd_nm varchar NULL,
                nsm_id varchar NULL,
                nsm_nm varchar NULL,
                grsm_id varchar NULL,
                grsm_nm varchar NULL,
                rsm_id varchar NULL,
                rsm_nm varchar NULL,
                ss_id varchar NULL,
                ss_nm varchar NULL,
                distributor_id varchar NULL,
                distributor_nm varchar NULL,
                sls_id varchar NULL,
                sls_nm varchar NULL,
                opr_type varchar NULL,
                salesforce_div_id varchar NULL,
                salesforce_div_nm varchar NULL,
                gsalesforce_id varchar NULL,
                gsalesforce_nm varchar NULL,
                cust_id varchar NULL,
                cust_nm varchar NULL,
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
                nobrs numeric NULL,
                route numeric NULL,
                slimit numeric NULL,
                hsenin varchar NULL,
                hselasa varchar NULL,
                hrabu varchar NULL,
                hkamis varchar NULL,
                hjumat varchar NULL,
                hsabtu varchar NULL,
                hminggu varchar NULL,
                visit1 varchar NULL,
                visit2 varchar NULL,
                visit3 varchar NULL,
                visit4 varchar NULL,
                cycle_kunjungan text NULL,
                provinsi_code varchar NULL,
                provinsi_name varchar NULL,
                kabupaten_code varchar NULL,
                kabupaten_name varchar NULL,
                kecamatan_code varchar NULL,
                kecamatan_name varchar NULL,
                kelurahan_code varchar NULL,
                kelurahan_name varchar NULL,
                latitude varchar NULL,
                longitude varchar NULL,
                barcode varchar NULL,
                cphone1 varchar NULL,
                regdate timestamp NULL,
                flagbon varchar NULL,
                flagpay varchar NULL,
                ogrp_id varchar NULL,
                ccontact varchar NULL,
                custadd1 varchar NULL,
                custadd2 varchar NULL,
                flagcust varchar NULL,
                deli_add1 varchar NULL,
                oclass_id varchar NULL,
                flagcredit varchar NULL,
                lastclass varchar NULL,
                gdisc_id varchar NULL,
                otype_id varchar NULL,
                ogrp1_id varchar NULL,
                ogrp2_id varchar NULL,
                ospec_id varchar NULL,
                pasar_id varchar NULL,
                gprice_id varchar NULL,
                flaglimit varchar NULL,
                indkey_id varchar NULL,
                last_type varchar NULL,
                climit numeric NULL
            ) PARTITION BY RANGE (tahun, periode);

            ALTER TABLE IF EXISTS bift.bronze_cb 
                ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT CURRENT_TIMESTAMP,
                ADD COLUMN IF NOT EXISTS barcode varchar NULL,
                ADD COLUMN IF NOT EXISTS cphone1 varchar NULL,
                ADD COLUMN IF NOT EXISTS regdate timestamp NULL,
                ADD COLUMN IF NOT EXISTS flagbon varchar NULL,
                ADD COLUMN IF NOT EXISTS flagpay varchar NULL,
                ADD COLUMN IF NOT EXISTS ogrp_id varchar NULL,
                ADD COLUMN IF NOT EXISTS ccontact varchar NULL,
                ADD COLUMN IF NOT EXISTS custadd1 varchar NULL,
                ADD COLUMN IF NOT EXISTS custadd2 varchar NULL,
                ADD COLUMN IF NOT EXISTS flagcust varchar NULL,
                ADD COLUMN IF NOT EXISTS deli_add1 varchar NULL,
                ADD COLUMN IF NOT EXISTS oclass_id varchar NULL,
                ADD COLUMN IF NOT EXISTS flagcredit varchar NULL,
                ADD COLUMN IF NOT EXISTS lastclass varchar NULL,
                ADD COLUMN IF NOT EXISTS gdisc_id varchar NULL,
                ADD COLUMN IF NOT EXISTS otype_id varchar NULL,
                ADD COLUMN IF NOT EXISTS ogrp1_id varchar NULL,
                ADD COLUMN IF NOT EXISTS ogrp2_id varchar NULL,
                ADD COLUMN IF NOT EXISTS ospec_id varchar NULL,
                ADD COLUMN IF NOT EXISTS pasar_id varchar NULL,
                ADD COLUMN IF NOT EXISTS gprice_id varchar NULL,
                ADD COLUMN IF NOT EXISTS flaglimit varchar NULL,
                ADD COLUMN IF NOT EXISTS indkey_id varchar NULL,
                ADD COLUMN IF NOT EXISTS last_type varchar NULL,
                ADD COLUMN IF NOT EXISTS climit numeric NULL;

            DO $$
            DECLARE
                y INT;
                p INT;
                y_next INT;
                p_next INT;
            BEGIN
                FOR y IN 2026..2026 LOOP
                    FOR p IN 1..12 LOOP
                        IF p = 12 THEN
                            y_next := y + 1;
                            p_next := 1;
                        ELSE
                            y_next := y;
                            p_next := p + 1;
                        END IF;

                        EXECUTE format(
                            'CREATE TABLE IF NOT EXISTS bift.bronze_cb_p%s_%s PARTITION OF bift.bronze_cb FOR VALUES FROM (%s, %s) TO (%s, %s);',
                            y, LPAD(p::text, 2, '0'), y, p, y_next, p_next
                        );
                    END LOOP;
                END LOOP;
                EXECUTE 'CREATE TABLE IF NOT EXISTS bift.bronze_cb_default PARTITION OF bift.bronze_cb DEFAULT;';
            END $$;
        """,
        indexes=[
          {'columns': ['tahun', 'periode', 'distributor_id', 'cust_id'],         'type': 'btree'},
          {'columns': ['tahun', 'periode', 'distributor_id', 'sls_id', 'cust_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'distributor_id'],                     'type': 'btree'},
          {'columns': ['distributor_id', 'sls_id', 'cust_id'],                    'type': 'btree'},
          {'columns': ['updated_at'],                                             'type': 'btree'}
        ]
    )
}}

WITH customer_with_location AS (
    SELECT DISTINCT ON (f.subdist_id, f.custno)
        f.subdist_id AS distributor_id,
        f.custno AS cust_id,
        f.custname AS cust_nm,
        f.barcode,
        f.cphone1,
        f.regdate,
        f.flagbon,
        f.flagpay,
        f.ogrp_id,
        f.ccontact,
        f.custadd1,
        f.custadd2,
        f.flagcust,
        f.deli_add1,
        f.oclass_id,
        f.flagcredit,
        f.last_class AS lastclass,
        f.gdisc_id,
        f.otype_id,
        f.ogrp1_id,
        f.ogrp2_id,
        f.ospec_id,
        f.pasar_id,
        f.gprice_id,
        f.flaglimit,
        f.indkey_id,
        f.last_type,
        f.climit,
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
    sh.source_schema,
    dfs._airbyte_extracted_at,
    CURRENT_TIMESTAMP AS updated_at,
    dfs.tahun,
    dfs.periode,
    dfs.tahun_periode,

    -- 1. Sales Hierarchy Details (FIRST)
    sh.gdiv_id,
    sh.gdiv_nm,
    sh.sd_id,
    sh.sd_nm,
    sh.nsm_id,
    sh.nsm_nm,
    sh.grsm_id,
    sh.grsm_nm,
    sh.rsm_id,
    sh.rsm_nm,
    sh.ss_id,
    sh.ss_nm,
    dfs.distributor_id,
    sh.distributor_nm,
    dfs.sls_id,
    sh.sls_nm,
    sh.opr_type,
    sh.salesforce_div_id,
    sh.salesforce_div_nm,
    sh.gsalesforce_id,
    sh.gsalesforce_nm,

    -- 2. Customer & Outlet Details
    dfs.cust_id,
    cwl.cust_nm,
    dfs.channel_id,
    dfs.channel_nm,
    dgc.group_channel_id,
    dgc.group_channel_nm,
    dfs.flag_aktif,
    dfs.group_outlet,
    dfs.salesforce_id,
    mmgs.gsalesforce1_id,
    mmgs.gsalesforce1_nm,
    mmgs.gsalesforce2_id,
    mmgs.gsalesforce2_nm,
    mmgs.salesforce_nm,
    dfs.team_id,
    dfs.nobrs,
    dfs.route,
    dfs.slimit,
    dfs.hsenin,
    dfs.hselasa,
    dfs.hrabu,
    dfs.hkamis,
    dfs.hjumat,
    dfs.hsabtu,
    dfs.hminggu,
    dfs.visit1,
    dfs.visit2,
    dfs.visit3,
    dfs.visit4,
    dfs.cycle_kunjungan,

    -- 3. Location Details
    cwl.provinsi_code,
    cwl.provinsi_name,
    cwl.kabupaten_code,
    cwl.kabupaten_name,
    cwl.kecamatan_code,
    cwl.kecamatan_name,
    cwl.kelurahan_code,
    cwl.kelurahan_name,
    cwl.latitude,
    cwl.longitude,

    -- 4. Customer Master Details
    cwl.barcode,
    cwl.cphone1,
    cwl.regdate,
    cwl.flagbon,
    cwl.flagpay,
    cwl.ogrp_id,
    cwl.ccontact,
    cwl.custadd1,
    cwl.custadd2,
    cwl.flagcust,
    cwl.deli_add1,
    cwl.oclass_id,
    cwl.flagcredit,
    cwl.lastclass,
    cwl.gdisc_id,
    cwl.otype_id,
    cwl.ogrp1_id,
    cwl.ogrp2_id,
    cwl.ospec_id,
    cwl.pasar_id,
    cwl.gprice_id,
    cwl.flaglimit,
    cwl.indkey_id,
    cwl.last_type,
    cwl.climit
FROM bift.dim_fcustsls dfs
INNER JOIN bift.dim_salesman_hierarchy sh 
    ON dfs.distributor_id = sh.distributor_id
   AND dfs.sls_id         = sh.sls_id
   AND (
        sh.termin_year IS NULL
        OR dfs.tahun < sh.termin_year
        OR (dfs.tahun = sh.termin_year AND dfs.periode <= sh.termin_period)
   )
LEFT JOIN bift.dim_group_channel dgc
    ON dfs.channel_id = dgc.channel_id
   AND sh.source_schema = dgc.source_schema
LEFT JOIN bift.dim_mapping_group_salesforce mmgs
    ON dfs.salesforce_id = mmgs.salesforce_id
   AND sh.source_schema = mmgs.source_schema
LEFT JOIN customer_with_location cwl
    ON dfs.distributor_id = cwl.distributor_id 
   AND dfs.cust_id = cwl.cust_id
WHERE dfs.channel_id != '999'
  AND dfs.flag_aktif = 'Y'
  AND dfs.salesforce_id NOT IN ('999', '116', '213', '222')
{% if is_incremental() %}
  {% if var('periode', none) is not none and var('tahun', none) is not none %}
    {# Manual backfill: dbt run --vars '{"periode": 8, "tahun": 2026}' #}
    AND dfs.periode = {{ var('periode') }}
    AND dfs.tahun = {{ var('tahun') }}
  {% else %}
    {# Auto-detect: check directly from physical dim_fcustsls table #}
    AND dfs._airbyte_extracted_at > (
        SELECT COALESCE(MAX(_airbyte_extracted_at), '1970-01-01'::timestamptz)
        FROM {{ this }}
    )
  {% endif %}
{% endif %}
