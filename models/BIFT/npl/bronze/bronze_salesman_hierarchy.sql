{{
    config(
        schema='bift',
        materialized='table',
        alias='bronze_salesman_hierarchy',
        indexes=[
          {
            'columns': ['distributor_id', 'sls_id'],
            'type': 'btree'
          }
        ]
    )
}}

WITH cycle_lookup AS (
    SELECT
        cdate::date AS cycle_date,
        year::int   AS period_year,
        period::int AS period_num
    FROM spx.m_cycle3
),

combined_hierarchy AS (
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
        d.distributor_nm,
        c.sls_id,
        COALESCE(t.termin_date, 'Active') AS termin_date,
        mc.period_year                    AS termin_year,
        mc.period_num                     AS termin_period,
        h._airbyte_extracted_at
    FROM raw_ficom_m1.mv_salesman_hierarchy_bi h
    JOIN raw_ficom_m1.m_employee e
      ON h.ss_id = e.emp_id
     AND e.terminate_date IS NULL
    JOIN bift.dim_salesman_spv c
      ON c.sls_id = h.sls_id
     AND c.distributor_id = h.distributor_id
     AND c.source_schema = 'm1'
    JOIN raw_ficom_m1.m_distributor d
      ON c.distributor_id = d.distributor_id
     AND COALESCE(d.flag_nonsis, 'N') != 'Y'
    LEFT JOIN (
        SELECT DISTINCT ON (spv_id, sls_id, distributor_id)
            spv_id, sls_id, distributor_id, termin_date
        FROM raw_ficom_m1.dim_sls_termin
        ORDER BY spv_id, sls_id, distributor_id, 
                 CASE WHEN LOWER(termin_date) = 'active' THEN 1 ELSE 2 END,
                 termin_date DESC
    ) t
      ON t.spv_id = h.ss_id
     AND t.sls_id = c.sls_id
     AND t.distributor_id = c.distributor_id
    LEFT JOIN cycle_lookup mc
      ON mc.cycle_date = CASE 
          WHEN t.termin_date IS NOT NULL AND LOWER(t.termin_date) != 'active'
          THEN t.termin_date::date
      END

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
        d.distributor_nm,
        c.sls_id,
        COALESCE(t.termin_date, 'Active') AS termin_date,
        mc.period_year                    AS termin_year,
        mc.period_num                     AS termin_period,
        h._airbyte_extracted_at
    FROM raw_ficom_m2.mv_salesman_hierarchy_bi h
    JOIN raw_ficom_m2.m_employee e
      ON h.ss_id = e.emp_id
     AND e.terminate_date IS NULL
    JOIN bift.dim_salesman_spv c
      ON c.sls_id = h.sls_id
     AND c.distributor_id = h.distributor_id
     AND c.source_schema = 'm2'
    JOIN raw_ficom_m2.m_distributor d
      ON c.distributor_id = d.distributor_id
     AND COALESCE(d.flag_nonsis, 'N') != 'Y'
    LEFT JOIN (
        SELECT DISTINCT ON (spv_id, sls_id, distributor_id)
            spv_id, sls_id, distributor_id, termin_date
        FROM raw_ficom_m2.dim_sls_termin
        ORDER BY spv_id, sls_id, distributor_id, 
                 CASE WHEN LOWER(termin_date) = 'active' THEN 1 ELSE 2 END,
                 termin_date DESC
    ) t
      ON t.spv_id = h.ss_id
     AND t.sls_id = c.sls_id
     AND t.distributor_id = c.distributor_id
    LEFT JOIN cycle_lookup mc
      ON mc.cycle_date = CASE 
          WHEN t.termin_date IS NOT NULL AND LOWER(t.termin_date) != 'active'
          THEN t.termin_date::date
      END

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
        d.distributor_nm,
        c.sls_id,
        COALESCE(t.termin_date, 'Active') AS termin_date,
        mc.period_year                    AS termin_year,
        mc.period_num                     AS termin_period,
        h._airbyte_extracted_at
    FROM raw_ficom_m3.mv_salesman_hierarchy_bi h
    JOIN raw_ficom_m3.m_employee e
      ON h.ss_id = e.emp_id
     AND e.terminate_date IS NULL
    JOIN bift.dim_salesman_spv c
      ON c.sls_id = h.sls_id
     AND c.distributor_id = h.distributor_id
     AND c.source_schema = 'm3'
    JOIN raw_ficom_m3.m_distributor d
      ON c.distributor_id = d.distributor_id
     AND COALESCE(d.flag_nonsis, 'N') != 'Y'
    LEFT JOIN (
        SELECT DISTINCT ON (spv_id, sls_id, distributor_id)
            spv_id, sls_id, distributor_id, termin_date
        FROM raw_ficom_m3.dim_sls_termin
        ORDER BY spv_id, sls_id, distributor_id, 
                 CASE WHEN LOWER(termin_date) = 'active' THEN 1 ELSE 2 END,
                 termin_date DESC
    ) t
      ON t.spv_id = h.ss_id
     AND t.sls_id = c.sls_id
     AND t.distributor_id = c.distributor_id
    LEFT JOIN cycle_lookup mc
      ON mc.cycle_date = CASE 
          WHEN t.termin_date IS NOT NULL AND LOWER(t.termin_date) != 'active'
          THEN t.termin_date::date
      END
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
    h.distributor_nm,
    
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
    sm.gsalesforce_nm,

    -- 8. Salesman Termination Metadata (from dim_sls_termin + spx.m_cycle3)
    h.termin_date,
    h.termin_year,
    h.termin_period

FROM combined_hierarchy h
LEFT JOIN bift.dim_salesman sm
       ON h.distributor_id = sm.distributor_id
      AND h.sls_id        = sm.sls_id
WHERE sm.sls_id IS NOT NULL
  -- Cross-division filtering based on salesman name (sls_nm) division tags
  AND (
      -- 1. Under SD CWC (WF0218 / CWC): exclude salesmen tagged with BIS/M3/M2 in name UNLESS also tagged as CWC
      ( (h.sd_id = 'WF0218' OR (h.source_schema = 'm1' AND h.sd_nm ILIKE '%CWC%'))
        AND NOT (
            (sm.sls_nm ~* '((^|[^a-zA-Z])BIS([^a-zA-Z]|$)|(^|[^a-zA-Z])BIS-|(^|[^a-zA-Z])BISC|(^|[^a-zA-Z])BISK)' OR sm.sls_nm ~* '((^|[^a-zA-Z])M3([^a-zA-Z]|$)|(^|[^a-zA-Z])M3-)' OR sm.sls_nm ~* '((^|[^a-zA-Z])M2([^a-zA-Z]|$)|(^|[^a-zA-Z])M2-|(^|[^a-zA-Z])M245|(^|[^a-zA-Z])MU-)')
            AND NOT (sm.sls_nm ~* '((^|[^a-zA-Z])CWC([^a-zA-Z]|$)|(^|[^a-zA-Z])CWC-)')
        )
      )
      OR
      -- 2. Under SD BIS (WF0217 / BIS): exclude salesmen tagged with CWC/M3/M2 in name UNLESS also tagged as BIS
      ( (h.sd_id = 'WF0217' OR (h.source_schema = 'm1' AND h.sd_nm ILIKE '%BIS%'))
        AND NOT (
            (sm.sls_nm ~* '((^|[^a-zA-Z])CWC([^a-zA-Z]|$)|(^|[^a-zA-Z])CWC-)' OR sm.sls_nm ~* '((^|[^a-zA-Z])M3([^a-zA-Z]|$)|(^|[^a-zA-Z])M3-)' OR sm.sls_nm ~* '((^|[^a-zA-Z])M2([^a-zA-Z]|$)|(^|[^a-zA-Z])M2-|(^|[^a-zA-Z])M245|(^|[^a-zA-Z])MU-)')
            AND NOT (sm.sls_nm ~* '((^|[^a-zA-Z])BIS([^a-zA-Z]|$)|(^|[^a-zA-Z])BIS-|(^|[^a-zA-Z])BISC|(^|[^a-zA-Z])BISK)')
        )
      )
      OR
      -- 3. Under SD M3 (WF0221 / m3): exclude salesmen tagged with CWC/BIS/M2 in name UNLESS also tagged as M3
      ( (h.sd_id = 'WF0221' OR h.source_schema = 'm3')
        AND NOT (
            (sm.sls_nm ~* '((^|[^a-zA-Z])CWC([^a-zA-Z]|$)|(^|[^a-zA-Z])CWC-)' OR sm.sls_nm ~* '((^|[^a-zA-Z])BIS([^a-zA-Z]|$)|(^|[^a-zA-Z])BIS-|(^|[^a-zA-Z])BISC|(^|[^a-zA-Z])BISK)' OR sm.sls_nm ~* '((^|[^a-zA-Z])M2([^a-zA-Z]|$)|(^|[^a-zA-Z])M2-|(^|[^a-zA-Z])M245|(^|[^a-zA-Z])MU-)')
            AND NOT (sm.sls_nm ~* '((^|[^a-zA-Z])M3([^a-zA-Z]|$)|(^|[^a-zA-Z])M3-)')
        )
      )
      OR
      -- 4. Under SD M245 (WF0220 / m2): exclude salesmen tagged with CWC/BIS/M3 in name UNLESS also tagged as M2
      ( (h.sd_id = 'WF0220' OR h.source_schema = 'm2')
        AND NOT (
            (sm.sls_nm ~* '((^|[^a-zA-Z])CWC([^a-zA-Z]|$)|(^|[^a-zA-Z])CWC-)' OR sm.sls_nm ~* '((^|[^a-zA-Z])BIS([^a-zA-Z]|$)|(^|[^a-zA-Z])BIS-|(^|[^a-zA-Z])BISC|(^|[^a-zA-Z])BISK)' OR sm.sls_nm ~* '((^|[^a-zA-Z])M3([^a-zA-Z]|$)|(^|[^a-zA-Z])M3-)')
            AND NOT (sm.sls_nm ~* '((^|[^a-zA-Z])M2([^a-zA-Z]|$)|(^|[^a-zA-Z])M2-|(^|[^a-zA-Z])M245|(^|[^a-zA-Z])MU-)')
        )
      )
  )
  -- Exclude non-salesman accounts (Office, Gudang, Opname, etc.)
  AND (
      sm.sls_nm IS NULL OR NOT (
          sm.sls_nm ILIKE '%PENJUALAN KANTOR%' OR
          sm.sls_nm ILIKE '%PENJUALAN%' OR
          sm.sls_nm ILIKE '%KANTOR%' OR
          sm.sls_nm ILIKE '%OPNAME%' OR
          sm.sls_nm ILIKE '%GUDANG%' OR
          sm.sls_nm ILIKE '%SALES OFFICE%' OR
          sm.sls_nm ILIKE '%OFFICE%' OR
          sm.sls_nm ILIKE '%TMT%' OR
          sm.sls_nm ILIKE '%TOPPING%' OR
          sm.sls_nm ILIKE '% MT %' OR
          sm.sls_nm ILIKE '% MTI %'
          sm.sls_nm ILIKE '%-MTI %'
      )
  )
