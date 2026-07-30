{{
    config(
        materialized='ephemeral'
    )
}}

WITH combined_staging AS (
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
    channel_id,
    flag_aktif,
    group_outlet,
    salesforce_id,
    team_id,
    hrabu,
    nobrs,
    route,
    hjumat,
    hkamis,
    hsabtu,
    hsenin,
    slimit,
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
    END                                                     AS cycle_kunjungan,
    hminggu,
    hselasa
FROM latest_staging_per_period
