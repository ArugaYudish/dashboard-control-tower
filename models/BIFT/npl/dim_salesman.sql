{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_salesman',
        indexes=[
          {'columns': ['distributor_id', 'sls_id'], 'type': 'btree'},
          {'columns': ['salesforce_id'], 'type': 'btree'}
        ]
    )
}}

WITH combined_salesman AS (
    SELECT 
        'm1' AS source_schema,
        distributor_id,
        sls_id,
        sls_nm,
        team_id,
        opr_type,
        salesforce_id,
        upd_date,
        trans_date,
        _airbyte_extracted_at
    FROM raw_ficom_m1.m_salesman

    UNION ALL

    SELECT 
        'm2' AS source_schema,
        distributor_id,
        sls_id,
        sls_nm,
        team_id,
        opr_type,
        salesforce_id,
        upd_date,
        trans_date,
        _airbyte_extracted_at
    FROM raw_ficom_m2.m_salesman

    UNION ALL

    SELECT 
        'm3' AS source_schema,
        distributor_id,
        sls_id,
        sls_nm,
        team_id,
        opr_type,
        salesforce_id,
        upd_date,
        trans_date,
        _airbyte_extracted_at
    FROM raw_ficom_m3.m_salesman
),

-- Deduplicate salesforce mapping by salesforce_id
combined_salesforce_mapping AS (
    SELECT DISTINCT ON (salesforce_id)
        div_id,
        div_nm,
        priority,
        salesforce_id,
        salesforce_nm,
        gsalesforce_id,
        gsalesforce_nm
    FROM raw_ficom_m2.m_mapping_group_salesforce
    WHERE salesforce_id IS NOT NULL
    ORDER BY salesforce_id, _airbyte_extracted_at DESC NULLS LAST
),

dedup_salesman AS (
    SELECT DISTINCT ON (distributor_id, sls_id)
        source_schema,
        distributor_id,
        sls_id,
        sls_nm,
        team_id,
        opr_type,
        salesforce_id,
        upd_date,
        trans_date
    FROM combined_salesman
    WHERE distributor_id IS NOT NULL AND sls_id IS NOT NULL
    ORDER BY 
        distributor_id, 
        sls_id, 
        upd_date DESC NULLS LAST, 
        trans_date DESC NULLS LAST
)

SELECT 
    s.source_schema,
    s.distributor_id,
    s.sls_id,
    s.sls_nm,
    s.team_id,
    s.opr_type,
    s.salesforce_id,
    
    -- Mapped Salesforce Group Columns
    sf.div_id               AS salesforce_div_id,
    sf.div_nm               AS salesforce_div_nm,
    sf.priority             AS salesforce_priority,
    sf.salesforce_nm,
    sf.gsalesforce_id,
    sf.gsalesforce_nm,
    
    s.upd_date,
    s.trans_date
FROM dedup_salesman s
LEFT JOIN combined_salesforce_mapping sf
       ON s.salesforce_id = sf.salesforce_id