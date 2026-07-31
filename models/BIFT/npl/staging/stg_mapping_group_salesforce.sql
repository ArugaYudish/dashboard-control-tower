{{
    config(
        materialized='ephemeral'
    )
}}

SELECT DISTINCT ON (salesforce_id)
    salesforce_id,
    salesforce_nm,
    gsalesforce_id,
    gsalesforce_nm,
    div_id,
    div_nm
FROM (
    SELECT salesforce_id, salesforce_nm, gsalesforce_id, gsalesforce_nm, div_id, div_nm
    FROM raw_ficom_m1.m_mapping_group_salesforce

    UNION ALL

    SELECT salesforce_id, salesforce_nm, gsalesforce_id, gsalesforce_nm, div_id, div_nm
    FROM raw_ficom_m2.m_mapping_group_salesforce

    UNION ALL

    SELECT salesforce_id, salesforce_nm, gsalesforce_id, gsalesforce_nm, div_id, div_nm
    FROM raw_ficom_m3.m_mapping_group_salesforce
) AS combined
ORDER BY salesforce_id
