{{
    config(
        materialized = 'table',
        indexes = [
            {'columns': ['year', 'period', 'week']},
            {'columns': ['report_date']},
            {'columns': ['sd_id', 'rsm_id', 'ss_id']},
            {'columns': ['distributor_id', 'sls_id', 'outlet_id']},
            {'columns': ['pcode']},
            {'columns': ['subbrand_id']},
            {'columns': ['gsalesforce_id']},
            {'columns': ['group_channel_id']}
        ]
    )
}}

WITH 
-- 1. HIERARKI SALESMAN M3 (EMPLOYEE AKTIF)
active_hierarchy AS (
    SELECT DISTINCT 
        a.sd_id, a.sd_nm,
        a.nsm_id, a.nsm_nm,
        a.grsm_id, a.grsm_nm,
        a.rsm_id, a.rsm_nm,
        a.ss_id, a.ss_nm,
        c.sls_id::varchar AS sls_id,
        COALESCE(ms.sls_nm, 'UNKNOWN / UNMAPPED') AS sls_nm,
        c.distributor_id::varchar AS distributor_id,
        COALESCE(md.distributor_nm, 'UNKNOWN') AS distributor_nm
    FROM raw_ficom_m3.v_salesman_hierarchy a
    JOIN raw_ficom_m3.m_employee b ON a.ss_id = b.emp_id
    JOIN raw_ficom_m3.m_salesman_spv c ON c.sls_id = a.sls_id AND c.distributor_id = a.distributor_id
    LEFT JOIN raw_ficom_m3.m_salesman ms ON c.distributor_id = ms.distributor_id AND c.sls_id = ms.sls_id
    LEFT JOIN raw_ficom_m3.m_distributor md ON c.distributor_id = md.distributor_id
    WHERE b.terminate_date IS NULL
),

-- 2. BASELINE CUSTOMER BASE (DEDUP 1 TOKO PER DISTRIBUTOR & SALESMAN PER BULAN)
cte_cb_snapshot AS (
    SELECT 
        st.distributor_id::varchar AS distributor_id,
        st.sls_id::varchar AS sls_id,
        st.cust_id::varchar AS cust_id,
        st.periode::int AS period,
        st.tahun::int AS year,
        st.channel_id::varchar AS channel_id,
        st.salesforce_id::varchar AS salesforce_id,
        st.upd_date,
        MAX(st.upd_date) OVER (PARTITION BY st.distributor_id::varchar, st.tahun, st.periode) AS upd_date_terakhir
    FROM raw_ficom_m3.v_fcustsls_staging st
    WHERE st.flag_aktif = 'Y'
      AND st.salesforce_id::varchar NOT IN ('999', '116', '213', '222')
),
cte_cb_dedup AS (
    SELECT DISTINCT ON (s.distributor_id, s.cust_id, s.year, s.period)
        s.distributor_id, 
        s.sls_id, 
        s.cust_id AS outlet_id, 
        s.year, 
        s.period,
        s.channel_id,
        s.salesforce_id
    FROM cte_cb_snapshot s
    WHERE s.upd_date = s.upd_date_terakhir
    ORDER BY s.distributor_id, s.cust_id, s.year, s.period DESC, s.upd_date DESC
),

-- 3. TARGET CALL HARIAN (KPL)
cte_target_call AS (
    SELECT 
        distributor_id::varchar AS distributor_id,
        sls_id::varchar AS sls_id,
        tgl::date AS report_date,
        SUM(tgt_call::int) AS tgt_call_daily
    FROM raw_ficom_m3.m_nmrc_subdetail
    GROUP BY distributor_id, sls_id, tgl
),

-- 4. KONSOLIDASI SELURUH POPULASI TOKO (CB + REALISASI UNMAPPED)
cte_all_outlets AS (
    -- Toko dari CB Baseline
    SELECT 
        distributor_id, sls_id, outlet_id, year, period, channel_id, salesforce_id,
        1 AS is_cb_active
    FROM cte_cb_dedup
    
    UNION
    
    -- Toko dari Realisasi Dashboard (Mencakup toko unmapped / transaksi luar CB)
    SELECT DISTINCT 
        distributor_id, sls_id, outlet_id, year, period, group_channel_id AS channel_id, salesforce_id,
        0 AS is_cb_active
    FROM {{ ref('gold_grading_dashboard') }}
)

-- MAIN MODEL FINAL (LEVEL PCODE)
SELECT 
    o.year,
    o.period,
    COALESCE(act.week, 0) AS week,
    act.report_date,
    
    -- HIERARKI PENJUALAN M3 (LEFT JOIN DENGAN FALLBACK UNMAPPED AGAR DILUAR M3 TIDAK TERBUANG)
    COALESCE(ah.sd_id, 'UNMAPPED') AS sd_id, 
    COALESCE(ah.sd_nm, 'UNMAPPED') AS sd_nm,
    COALESCE(ah.nsm_id, 'UNMAPPED') AS nsm_id, 
    COALESCE(ah.nsm_nm, 'UNMAPPED') AS nsm_nm,
    COALESCE(ah.grsm_id, 'UNMAPPED') AS grsm_id, 
    COALESCE(ah.grsm_nm, 'UNMAPPED') AS grsm_nm,
    COALESCE(ah.rsm_id, 'UNMAPPED') AS rsm_id, 
    COALESCE(ah.rsm_nm, 'UNMAPPED') AS rsm_nm,
    COALESCE(ah.ss_id, 'UNMAPPED') AS ss_id, 
    COALESCE(ah.ss_nm, 'UNMAPPED') AS ss_nm,
    o.sls_id, 
    COALESCE(ah.sls_nm, 'UNKNOWN / UNMAPPED') AS sls_nm,
    o.distributor_id, 
    COALESCE(ah.distributor_nm, 'UNKNOWN') AS distributor_nm,
    o.outlet_id,
    
    -- SALESFORCE & CHANNEL
    COALESCE(act.salesforce_id, o.salesforce_id) AS salesforce_id,
    COALESCE(mgc.gsalesforce_id, 'UNMAPPED_GSALESFORCE') AS gsalesforce_id,
    COALESCE(mgc.gsalesforce_nm, 'OTHERS / UNMAPPED') AS gsalesforce_nm,
    COALESCE(mcs.group_channel_id, 'UNMAPPED_CHANNEL') AS group_channel_id,
    COALESCE(mcs.group_channel_nm, 'OTHERS / UNMAPPED') AS group_channel_nm,
    
    -- PRODUK & REALISASI (LEVEL PCODE & SUBBRAND UTUH)
    COALESCE(act.subbrand_id, 'NO_TRANSACTION') AS subbrand_id,
    COALESCE(act.subbrand_nm, 'NO TRANSACTION / UNVISITED') AS subbrand_nm,
    COALESCE(act.pcode, 'NO_PCODE') AS pcode,
    COALESCE(act.pcode_nm, 'NO PCODE / UNVISITED') AS pcode_nm,
    act.grade,
    
    -- METRICS
    o.is_cb_active,
    COALESCE(tc.tgt_call_daily, 0) AS tgt_call_daily,
    COALESCE(act.inv_qty, 0) AS inv_qty,
    COALESCE(act.inv_val, 0) AS inv_val,
    COALESCE(act.facing_qty, 0) AS facing_qty,
    CASE WHEN act.outlet_id IS NOT NULL THEN 1 ELSE 0 END AS is_visited

FROM cte_all_outlets o

-- LEFT JOIN 1: HIERARKI PENJUALAN M3 (TIDAK MEMBUANG SALES UNMAPPED)
LEFT JOIN active_hierarchy ah 
    ON o.distributor_id = ah.distributor_id 
   AND o.sls_id = ah.sls_id

-- LEFT JOIN 2: TRANSAKSI & IR DETAIL DARI FACT DASHBOARD (LEVEL PCODE)
LEFT JOIN {{ ref('gold_grading_dashboard') }} act
    ON o.distributor_id = act.distributor_id
   AND o.outlet_id = act.outlet_id
   AND o.year = act.year
   AND o.period = act.period

-- LEFT JOIN 3: TARGET CALL HARIAN
LEFT JOIN cte_target_call tc
    ON o.distributor_id = tc.distributor_id
   AND o.sls_id = tc.sls_id
   AND act.report_date = tc.report_date

-- LEFT JOIN 4: MASTER MAPPER
LEFT JOIN raw_ficom_m3.m_mapping_group_salesforce mgc 
    ON COALESCE(act.salesforce_id, o.salesforce_id) = mgc.salesforce_id::varchar

LEFT JOIN raw_ficom_m3.m_group_channels mcs 
    ON o.channel_id = mcs.channel_id::varchar