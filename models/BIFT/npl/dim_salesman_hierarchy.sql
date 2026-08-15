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
    SELECT DISTINCT
        'm1' AS source_schema,
        h.sd_id,
        h.sd_nm,
        h.nsm_id,
        h.nsm_nm,
        h.grsm_id,
        h.grsm_nm,
        h.rsm_id,
        h.rsm_nm,
        h.ss_id,
        h.ss_nm,
        c.distributor_id,
        c.sls_id,
        h._airbyte_extracted_at
    FROM raw_ficom_m1.v_salesman_hierarchy h
    JOIN raw_ficom_m1.m_employee e
      ON h.ss_id = e.emp_id
     AND e.terminate_date IS NULL
    JOIN raw_ficom_m1.m_salesman_spv c
      ON c.sls_id = h.sls_id
     AND c.distributor_id = h.distributor_id
    JOIN raw_ficom_m1.dim_sls_termin t
      ON t.spv_id = h.ss_id
     AND t.sls_id = c.sls_id
     AND t.distributor_id = c.distributor_id
     AND t.termin_date = 'Active'

    UNION ALL

    SELECT DISTINCT
        'm2' AS source_schema,
        h.sd_id,
        h.sd_nm,
        h.nsm_id,
        h.nsm_nm,
        h.grsm_id,
        h.grsm_nm,
        h.rsm_id,
        h.rsm_nm,
        h.ss_id,
        h.ss_nm,
        c.distributor_id,
        c.sls_id,
        h._airbyte_extracted_at
    FROM raw_ficom_m2.v_salesman_hierarchy h
    JOIN raw_ficom_m2.m_employee e
      ON h.ss_id = e.emp_id
     AND e.terminate_date IS NULL
    JOIN raw_ficom_m2.m_salesman_spv c
      ON c.sls_id = h.sls_id
     AND c.distributor_id = h.distributor_id
    JOIN raw_ficom_m2.dim_sls_termin t
      ON t.spv_id = h.ss_id
     AND t.sls_id = c.sls_id
     AND t.distributor_id = c.distributor_id
     AND t.termin_date = 'Active'

    UNION ALL

    SELECT DISTINCT
        'm3' AS source_schema,
        h.sd_id,
        h.sd_nm,
        h.nsm_id,
        h.nsm_nm,
        h.grsm_id,
        h.grsm_nm,
        h.rsm_id,
        h.rsm_nm,
        h.ss_id,
        h.ss_nm,
        c.distributor_id,
        c.sls_id,
        h._airbyte_extracted_at
    FROM raw_ficom_m3.v_salesman_hierarchy h
    JOIN raw_ficom_m3.m_employee e
      ON h.ss_id = e.emp_id
     AND e.terminate_date IS NULL
    JOIN raw_ficom_m3.m_salesman_spv c
      ON c.sls_id = h.sls_id
     AND c.distributor_id = h.distributor_id
    JOIN raw_ficom_m3.dim_sls_termin t
      ON t.spv_id = h.ss_id
     AND t.sls_id = c.sls_id
     AND t.distributor_id = c.distributor_id
     AND t.termin_date = 'Active'
)
SELECT 
    h.source_schema,

    -- 0. Grand Division (mapped via sd_id / source_schema)
    CASE
        WHEN h.sd_id = 'WF0221' OR h.source_schema = 'm3'                           THEN '03'
        WHEN h.sd_id = 'WF0218' OR (h.source_schema = 'm1' AND h.sd_nm ILIKE '%CWC%') THEN '06'
        WHEN h.sd_id = 'WF0217' OR (h.source_schema = 'm1' AND h.sd_nm ILIKE '%BIS%') THEN '05'
        WHEN h.sd_id = 'WF0220' OR h.source_schema = 'm2'                           THEN '10'
        ELSE ''
    END                                                     AS gdiv_id,

    CASE
        WHEN h.sd_id = 'WF0221' OR h.source_schema = 'm3'                           THEN 'M3'
        WHEN h.sd_id = 'WF0218' OR (h.source_schema = 'm1' AND h.sd_nm ILIKE '%CWC%') THEN 'CWC'
        WHEN h.sd_id = 'WF0217' OR (h.source_schema = 'm1' AND h.sd_nm ILIKE '%BIS%') THEN 'BIS'
        WHEN h.sd_id = 'WF0220' OR h.source_schema = 'm2'                           THEN 'M245'
        ELSE ''
    END                                                     AS gdiv_nm,

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
