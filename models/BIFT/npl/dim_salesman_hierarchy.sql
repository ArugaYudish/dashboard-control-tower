{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_salesman_hierarchy',
        indexes=[
          {
            'columns': ['distributor_id', 'sls_id'],
            'type': 'btree'
          }
        ]
    )
}}

WITH combined_hierarchy AS (
    SELECT 
        'm1' AS source_schema,
        sd_id,
        sd_nm,
        nsm_id,
        nsm_nm,
        grsm_id,
        grsm_nm,
        rsm_id,
        rsm_nm,
        ss_id,
        ss_nm,
        distributor_id,
        sls_id,
        _airbyte_extracted_at
    FROM raw_ficom_m1.v_salesman_hierarchy

    UNION ALL

    SELECT 
        'm2' AS source_schema,
        sd_id,
        sd_nm,
        nsm_id,
        nsm_nm,
        grsm_id,
        grsm_nm,
        rsm_id,
        rsm_nm,
        ss_id,
        ss_nm,
        distributor_id,
        sls_id,
        _airbyte_extracted_at
    FROM raw_ficom_m2.v_salesman_hierarchy

    UNION ALL

    SELECT 
        'm3' AS source_schema,
        sd_id,
        sd_nm,
        nsm_id,
        nsm_nm,
        grsm_id,
        grsm_nm,
        rsm_id,
        rsm_nm,
        ss_id,
        ss_nm,
        distributor_id,
        sls_id,
        _airbyte_extracted_at
    FROM raw_ficom_m3.v_salesman_hierarchy
)
SELECT 
    h.source_schema,
    
    -- 1. Sales Director (SD)
    h.sd_id,
    h.sd_nm,
    
    -- 2. National Sales Manager (NSM)
    h.nsm_id,
    h.nsm_nm,
    
    -- 3. Group Regional Sales Manager (GRSM)
    h.grsm_id,
    h.grsm_nm,
    
    -- 4. Regional Sales Manager (RSM)
    h.rsm_id,
    h.rsm_nm,
    
    -- 5. Sales Supervisor (SS)
    h.ss_id,
    h.ss_nm,
    
    -- 6. Distributor Details
    h.distributor_id,
    md.distributor_nm,
    
    -- 7. Salesman Details (Enriched from dim_salesman)
    h.sls_id,
    sm.sls_nm,
    sm.team_id,
    sm.opr_type,
    sm.salesforce_id,
    sm.salesforce_div_id,
    sm.salesforce_div_nm,
    sm.salesforce_nm,
    sm.gsalesforce_id,
    sm.gsalesforce_nm

FROM combined_hierarchy h
LEFT JOIN bift.dim_salesman sm
       ON h.distributor_id = sm.distributor_id
      AND h.sls_id        = sm.sls_id
LEFT JOIN spx.m_distributor md
        ON md.distributor_id = h.distributor_id