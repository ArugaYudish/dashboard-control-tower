{{
    config(
        schema='bift',
        materialized='table',
        alias='gold_npl_dashboard',
        pre_hook="SET LOCAL work_mem = '512MB';",
        indexes=[
          {'columns': ['date'], 'type': 'btree'},
          {'columns': ['year', 'period', 'week'], 'type': 'btree'},

          {'columns': ['sd_id', 'nsm_id', 'rsm_id', 'ss_id', 'distributor_id'], 'type': 'btree'},
          {'columns': ['distributor_id', 'sls_id', 'cust_id'], 'type': 'btree'},

          {'columns': ['gdiv_id', 'div_id', 'team_id', 'class_team_id'], 'type': 'btree'},
          {'columns': ['subbrand_id'], 'type': 'btree'},

          {'columns': ['group_channel_id', 'channel_id'], 'type': 'btree'},
          {'columns': ['provinsi_code', 'kabupaten_code'], 'type': 'btree'}
        ]
    )
}}

SELECT 
    -- 1. Date & Calendar Cycle
    c.year,
    c.period,
    c.week,
    s.ord_date::date                                        AS date,
    
    -- 2. Invoice Details
    s.inv_no,
    s.inv_qty,
    s.inv_val,
    COALESCE(
        s.inv_qty::numeric / NULLIF(f.convunit2 * f.convunit3, 0), 
        0
    )                                                       AS qty_carton,
    
    -- 3. Sales Hierarchy (Root Level)
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
    
    -- 4. Distributor Info
    sh.distributor_id,
    sh.distributor_nm,
    
    -- 5. Salesman & Salesforce Info
    sh.sls_id,
    sh.sls_nm,
    sh.salesforce_id,
    sh.salesforce_nm,
    sh.gsalesforce_id,
    sh.gsalesforce_nm,
    sh.salesforce_div_id,
    sh.salesforce_div_nm,
    
    -- 6. Customer & Channel Info
    s.custno                                                AS cust_id,
    mc.cust_nm,
    TRIM(CONCAT_WS(' ', mc.address, mc.address2))           AS address,
    cs.channel_id,
    gc.channel_nm,
    gc.group_channel_id,
    gc.group_channel_nm,
    
    -- Visit Cycle Calculation
    CASE 
        WHEN CONCAT(cs.visit1, cs.visit2, cs.visit3, cs.visit4) = 'YYYY' THEN 'Weekly'
        WHEN CONCAT(cs.visit1, cs.visit2, cs.visit3, cs.visit4) = 'YTYT' THEN 'BiWeekly1'
        WHEN CONCAT(cs.visit1, cs.visit2, cs.visit3, cs.visit4) = 'TYTY' THEN 'BiWeekly2'
        WHEN CONCAT(cs.visit1, cs.visit2, cs.visit3, cs.visit4) = 'YTTT' THEN 'Monthly1'
        WHEN CONCAT(cs.visit1, cs.visit2, cs.visit3, cs.visit4) = 'TYTT' THEN 'Monthly2'
        WHEN CONCAT(cs.visit1, cs.visit2, cs.visit3, cs.visit4) = 'TTYT' THEN 'Monthly3'
        WHEN CONCAT(cs.visit1, cs.visit2, cs.visit3, cs.visit4) = 'TTTY' THEN 'Monthly4'
    END                                                     AS cycle_kunjungan,
    
    -- 7. Location Hierarchy (from dim_lokasi via dim_customer.kelurahan)
    loc.provinsi_code,
    loc.provinsi_name,
    loc.kabupaten_code,
    loc.kabupaten_name,
    loc.kecamatan_code,
    loc.kecamatan_name,
    loc.kelurahan_code,
    loc.kelurahan_name,
    
    -- 8. Product Info
    s.pcode,
    f.pcode_nm,
    f.div_id,
    f.div_nm,
    f.team_id,
    f.team_nm,
    f.class_team_id,
    f.class_team_nm,
    f.subbrand_id,
    f.subbrand_nm,
    f.gdiv_id,
    f.gdiv_nm,
    f.cat_id,
    f.cat_nm,
    f.sbu_id,
    f.sbu_nm,
    
    -- 9. Transaction & CB Flags
    CASE 
        WHEN COALESCE(s.inv_val, 0) > 0 THEN 1 
        ELSE 0 
    END                                                     AS is_transaction,
    
    CASE 
        WHEN cs.flag_aktif = 'Y' 
         AND cs.salesforce_id NOT IN ('999', '116', '213', '222') 
        THEN 1 
        ELSE 0 
    END                                                     AS is_cb

-- STEP 1: Top-Down Root (Sales Hierarchy Master)
FROM bift.dim_salesman_hierarchy sh

-- STEP 2: Sales Transactions (Filtered for status '905')
INNER JOIN raw_ho.vfsales_det s
        ON sh.distributor_id = s.subdist_id
       AND sh.sls_id        = s.slsno
       AND s.sts            = '905'

-- STEP 3: Calendar Cycle Mapping
LEFT JOIN spx.m_cycle3 c
        ON s.ord_date::date  = c.cdate::date

-- STEP 4: Monthly Customer Staging (Period snapshot)
LEFT JOIN bift.dim_fcustsls_staging cs
        ON s.subdist_id      = cs.distributor_id
       AND s.slsno           = cs.sls_id
       AND s.custno          = cs.cust_id
       AND c.year            = cs.tahun
       AND c.period          = cs.periode

-- STEP 5: Channel & Group Channel Lookup
LEFT JOIN bift.dim_group_channel gc
        ON cs.channel_id     = gc.channel_id

-- STEP 6: Customer Master Lookup
LEFT JOIN bift.dim_customer mc 
        ON s.subdist_id      = mc.distributor_id
       AND s.custno          = mc.cust_id

-- STEP 7: Location Hierarchy Lookup
LEFT JOIN bift.dim_lokasi loc
        ON mc.provinsi   = loc.provinsi_code
        AND mc.kabupaten = loc.kabupaten_code
        AND mc.kecamatan = loc.kecamatan_code
        AND mc.kelurahan = loc.kelurahan_code

-- STEP 8: Product Master Lookup
LEFT JOIN bift.dim_product f
        ON s.pcode           = f.pcode