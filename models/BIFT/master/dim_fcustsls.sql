{%- set ns = namespace() -%}
{%- do bift_resolve_cycle_window(ns, relation_schema='bift', relation_name='dim_fcustsls', default_lookback_weeks=2) -%}

{{
    config(
        schema='bift',
        materialized='incremental',
        alias='dim_fcustsls',
        incremental_strategy='append',
        pre_hook=[
            "SET LOCAL work_mem = '256MB'",
            "SELECT pg_advisory_xact_lock(hashtext('{{ this }}'))",
            "{{ bift_delete_target_periods('tp') }}"
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
    {% if is_incremental() and ns.filter_periods and (ns.period_pairs | length) > 0 %}
      AND (f.tahun, f.periode) IN (
          {%- for pair in ns.period_pairs -%}
          ({{ pair[0] }}, {{ pair[1] }}){% if not loop.last %}, {% endif %}
          {%- endfor -%}
      )
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
    {% if is_incremental() and ns.filter_periods and (ns.period_pairs | length) > 0 %}
      AND (f.tahun, f.periode) IN (
          {%- for pair in ns.period_pairs -%}
          ({{ pair[0] }}, {{ pair[1] }}){% if not loop.last %}, {% endif %}
          {%- endfor -%}
      )
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
    {% if is_incremental() and ns.filter_periods and (ns.period_pairs | length) > 0 %}
      AND (f.tahun, f.periode) IN (
          {%- for pair in ns.period_pairs -%}
          ({{ pair[0] }}, {{ pair[1] }}){% if not loop.last %}, {% endif %}
          {%- endfor -%}
      )
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
