{{
    config(
        schema='bift',
        materialized='incremental',
        alias='dim_fcustsls',
        unique_key=['distributor_id', 'sls_id', 'cust_id', 'tahun', 'periode', 'source_schema'],
        incremental_strategy='delete+insert',
        pre_hook="""
            CREATE TABLE IF NOT EXISTS bift.dim_fcustsls (
                source_schema text NULL,
                _airbyte_raw_id text NULL,
                _airbyte_extracted_at timestamptz NULL,
                _airbyte_meta jsonb NULL,
                _airbyte_generation_id int8 NULL,
                distributor_id varchar NULL,
                sls_id varchar NULL,
                cust_id varchar NULL,
                tahun numeric NULL,
                periode numeric NULL,
                tahun_periode numeric NULL,
                channel_id varchar NULL,
                channel_nm varchar NULL,
                group_channel_id varchar NULL,
                group_channel_nm varchar NULL,
                flag_aktif varchar NULL,
                group_outlet varchar NULL,
                salesforce_id varchar NULL,
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
                cycle_kunjungan text NULL
            ) PARTITION BY LIST (tahun_periode);

            DO $$
            DECLARE
                y INT;
                p INT;
                code INT;
            BEGIN
                FOR y IN 26..26 LOOP
                    FOR p IN 1..12 LOOP
                        code := y * 100 + p;
                        EXECUTE format('CREATE TABLE IF NOT EXISTS bift.dim_fcustsls_p%s PARTITION OF bift.dim_fcustsls FOR VALUES IN (%s);', code, code);
                    END LOOP;
                END LOOP;
                EXECUTE 'CREATE TABLE IF NOT EXISTS bift.dim_fcustsls_default PARTITION OF bift.dim_fcustsls DEFAULT;';
            END $$;
        """,
        indexes=[
            {'columns': ['tahun_periode', 'distributor_id'], 'type': 'btree'},
            {'columns': ['tahun', 'periode', 'distributor_id'], 'type': 'btree'},
            {'columns': ['distributor_id', 'sls_id', 'cust_id'], 'type': 'btree'},
            {'columns': ['source_schema', 'distributor_id', 'cust_id'], 'type': 'btree'}
        ]
    )
}}

WITH m1_staging AS (
    SELECT 
        'm1' AS source_schema,
        f.*,
        gc.channel_nm,
        gc.group_channel_id,
        gc.group_channel_nm
    FROM raw_ficom_m1.v_fcustsls_staging f
    INNER JOIN (
        SELECT DISTINCT ON (channel_id) *
        FROM raw_ficom_m1.m_group_channels
        ORDER BY channel_id
    ) gc ON f.channel_id = gc.channel_id
    {% if is_incremental() %}
      {% if var('periode', none) is not none and var('tahun', none) is not none %}
        WHERE f.periode = {{ var('periode') }}
          AND f.tahun = {{ var('tahun') }}
      {% else %}
        WHERE (f.tahun, f.periode) IN (
            SELECT DISTINCT tahun, periode
            FROM raw_ficom_m1.v_fcustsls_staging
            WHERE _airbyte_extracted_at > (
                SELECT COALESCE(MAX(_airbyte_extracted_at), '1970-01-01'::timestamptz)
                FROM {{ this }}
            )
        )
      {% endif %}
    {% endif %}
),

m2_staging AS (
    SELECT 
        'm2' AS source_schema,
        f.*,
        gc.channel_nm,
        gc.group_channel_id,
        gc.group_channel_nm
    FROM raw_ficom_m2.v_fcustsls_staging f
    INNER JOIN (
        SELECT DISTINCT ON (channel_id) *
        FROM raw_ficom_m2.m_group_channels
        ORDER BY channel_id
    ) gc ON f.channel_id = gc.channel_id
    {% if is_incremental() %}
      {% if var('periode', none) is not none and var('tahun', none) is not none %}
        WHERE f.periode = {{ var('periode') }}
          AND f.tahun = {{ var('tahun') }}
      {% else %}
        WHERE (f.tahun, f.periode) IN (
            SELECT DISTINCT tahun, periode
            FROM raw_ficom_m2.v_fcustsls_staging
            WHERE _airbyte_extracted_at > (
                SELECT COALESCE(MAX(_airbyte_extracted_at), '1970-01-01'::timestamptz)
                FROM {{ this }}
            )
        )
      {% endif %}
    {% endif %}
),

m3_staging AS (
    SELECT 
        'm3' AS source_schema,
        f.*,
        gc.channel_nm,
        gc.group_channel_id,
        gc.group_channel_nm
    FROM raw_ficom_m3.v_fcustsls_staging f
    INNER JOIN (
        SELECT DISTINCT ON (channel_id) *
        FROM raw_ficom_m3.m_group_channels
        ORDER BY channel_id
    ) gc ON f.channel_id = gc.channel_id
    {% if is_incremental() %}
      {% if var('periode', none) is not none and var('tahun', none) is not none %}
        WHERE f.periode = {{ var('periode') }}
          AND f.tahun = {{ var('tahun') }}
      {% else %}
        WHERE (f.tahun, f.periode) IN (
            SELECT DISTINCT tahun, periode
            FROM raw_ficom_m3.v_fcustsls_staging
            WHERE _airbyte_extracted_at > (
                SELECT COALESCE(MAX(_airbyte_extracted_at), '1970-01-01'::timestamptz)
                FROM {{ this }}
            )
        )
      {% endif %}
    {% endif %}
),

combined_staging AS (
    SELECT * FROM m1_staging
    UNION ALL
    SELECT * FROM m2_staging
    UNION ALL
    SELECT * FROM m3_staging
),

staging_with_max_date AS (
    SELECT
        *,
        MAX(upd_date) OVER (
            PARTITION BY source_schema, distributor_id, tahun, periode
        ) AS upd_date_terakhir
    FROM combined_staging
    WHERE cust_id IS NOT NULL 
      AND distributor_id IS NOT NULL
      AND tahun IS NOT NULL
      AND periode IS NOT NULL
),

latest_date_per_distributor AS (
    SELECT *
    FROM staging_with_max_date
    WHERE upd_date = upd_date_terakhir
),

latest_staging_per_period AS (
    SELECT DISTINCT ON (source_schema, distributor_id, cust_id, sls_id, tahun, periode)
        *
    FROM latest_date_per_distributor
    ORDER BY 
        source_schema,
        distributor_id,
        cust_id,
        sls_id,
        tahun DESC,
        periode DESC,
        upd_date DESC NULLS LAST,
        _airbyte_extracted_at DESC NULLS LAST
)

SELECT 
    source_schema,
    _airbyte_raw_id,
    _airbyte_extracted_at,
    _airbyte_meta,
    _airbyte_generation_id,
    distributor_id,
    sls_id,
    cust_id,
    tahun,
    periode,
    ((tahun % 100) * 100 + periode)::numeric AS tahun_periode,
    channel_id,
    channel_nm,
    group_channel_id,
    group_channel_nm,
    flag_aktif,
    group_outlet,
    salesforce_id,
    team_id,
    nobrs,
    route,
    slimit,
    hsenin,
    hselasa,
    hrabu,
    hkamis,
    hjumat,
    hsabtu,
    hminggu,
    visit1,
    visit2,
    visit3,
    visit4,
    CASE 
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'YYYY' THEN 'Weekly'
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'YTYT' THEN 'BiWeekly1'
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'TYTY' THEN 'BiWeekly2'
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'YTTT' THEN 'Monthly1'
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'TYTT' THEN 'Monthly2'
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'TTYT' THEN 'Monthly3'
        WHEN CONCAT(visit1, visit2, visit3, visit4) = 'TTTY' THEN 'Monthly4'
    END                                                     AS cycle_kunjungan
FROM latest_staging_per_period
