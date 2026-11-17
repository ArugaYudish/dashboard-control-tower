{%- set v_tahun = var('tahun', none) -%}
{%- set v_periode = var('periode', none) -%}

{%- if v_tahun is not none and v_periode is not none -%}
    {%- set target_tahun = v_tahun | int -%}
    {%- set target_periode = v_periode | int -%}
{%- elif execute -%}
    {%- set cycle_res = run_query("SELECT year::int AS tahun, period::int AS periode FROM spx.m_cycle3 WHERE cdate::date = CURRENT_DATE LIMIT 1") -%}
    {%- if cycle_res and (cycle_res.rows | length) > 0 -%}
        {%- set target_tahun = cycle_res.columns[0].values()[0] | int -%}
        {%- set target_periode = cycle_res.columns[1].values()[0] | int -%}
    {%- else -%}
        {%- set target_tahun = 2026 -%}
        {%- set target_periode = 1 -%}
    {%- endif -%}
{%- else -%}
    {%- set target_tahun = 2026 -%}
    {%- set target_periode = 1 -%}
{%- endif -%}

{%- set target_tahun_periode = ((target_tahun % 100) * 100 + target_periode) -%}

{{
    config(
        schema='bift',
        materialized='incremental',
        alias='dim_fcustsls',
        unique_key=['tahun_periode'],
        incremental_strategy='delete+insert',
        incremental_predicates=["DBT_INTERNAL_DEST.tahun_periode = " ~ target_tahun_periode],
        pre_hook=[
            "SET LOCAL work_mem = '256MB'"
        ],
        indexes=[
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
        NULL::varchar AS group_channel_id,
        NULL::varchar AS group_channel_nm
    FROM raw_ficom_m1.v_fcustsls_staging f
    INNER JOIN (
        SELECT DISTINCT ON (channel_id) channel_id, channel_nm
        FROM raw_ficom_m1.m_group_channels
        ORDER BY channel_id
    ) gc ON f.channel_id = gc.channel_id
    WHERE f.cust_id IS NOT NULL
      AND f.distributor_id IS NOT NULL
      AND f.tahun IS NOT NULL
      AND f.periode IS NOT NULL
    {% if is_incremental() %}
      AND f.periode = {{ target_periode }}
      AND f.tahun = {{ target_tahun }}
    {% endif %}
),

m2_staging AS (
    SELECT 
        'm2' AS source_schema,
        f.*,
        gc.channel_nm,
        NULL::varchar AS group_channel_id,
        NULL::varchar AS group_channel_nm
    FROM raw_ficom_m2.v_fcustsls_staging f
    INNER JOIN (
        SELECT DISTINCT ON (channel_id) channel_id, channel_nm
        FROM raw_ficom_m2.m_group_channels
        ORDER BY channel_id
    ) gc ON f.channel_id = gc.channel_id
    WHERE f.cust_id IS NOT NULL
      AND f.distributor_id IS NOT NULL
      AND f.tahun IS NOT NULL
      AND f.periode IS NOT NULL
    {% if is_incremental() %}
      AND f.periode = {{ target_periode }}
      AND f.tahun = {{ target_tahun }}
    {% endif %}
),

m3_staging AS (
    SELECT 
        'm3' AS source_schema,
        f.*,
        gc.channel_nm,
        NULL::varchar AS group_channel_id,
        NULL::varchar AS group_channel_nm
    FROM raw_ficom_m3.v_fcustsls_staging f
    INNER JOIN (
        SELECT DISTINCT ON (channel_id) channel_id, channel_nm
        FROM raw_ficom_m3.m_group_channels
        ORDER BY channel_id
    ) gc ON f.channel_id = gc.channel_id
    WHERE f.cust_id IS NOT NULL
      AND f.distributor_id IS NOT NULL
      AND f.tahun IS NOT NULL
      AND f.periode IS NOT NULL
    {% if is_incremental() %}
      AND f.periode = {{ target_periode }}
      AND f.tahun = {{ target_tahun }}
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
            PARTITION BY distributor_id, tahun, periode, source_schema
        ) AS upd_date_terakhir
    FROM combined_staging
),

latest_staging_per_period AS (
    SELECT DISTINCT ON (distributor_id, tahun, periode, sls_id, cust_id)
        *
    FROM staging_with_max_date
    WHERE upd_date = upd_date_terakhir
    ORDER BY 
        distributor_id,
        tahun,
        periode,
        sls_id,
        cust_id,
        upd_date DESC NULLS LAST,
        _airbyte_extracted_at DESC NULLS LAST,
        source_schema ASC
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
