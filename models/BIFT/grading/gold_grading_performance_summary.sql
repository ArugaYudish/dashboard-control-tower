{{
    config(
        materialized = 'table',
        indexes = [
            {'columns': ['year', 'period', 'week']},
            {'columns': ['report_date']},
            {'columns': ['sd_id', 'nsm_id', 'grsm_id', 'rsm_id', 'ss_id']},
            {'columns': ['distributor_id', 'sls_id', 'outlet_id']},
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

-- 2. BASELINE CUSTOMER BASE (1 TOKO UNIK PER DISTRIBUTOR & SALESMAN PER BULAN)
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
    JOIN active_hierarchy ah ON st.distributor_id::varchar = ah.distributor_id AND st.sls_id::varchar = ah.sls_id
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
        tc.distributor_id::varchar AS distributor_id,
        tc.sls_id::varchar AS sls_id,
        tc.tgl::date AS report_date,
        SUM(tc.tgt_call::int) AS tgt_call_daily
    FROM raw_ficom_m3.m_nmrc_subdetail tc
    JOIN active_hierarchy ah ON tc.distributor_id::varchar = ah.distributor_id AND tc.sls_id::varchar = ah.sls_id
    GROUP BY tc.distributor_id, tc.sls_id, tc.tgl
),

-- 4. KONSOLIDASI POPULASI OUTLET (CB + OUTLET REALISASI DARI DASHBOARD)
cte_all_outlets AS (
    -- Toko dari CB
    SELECT 
        distributor_id, sls_id, outlet_id, year, period, channel_id, salesforce_id,
        1 AS is_cb_active
    FROM cte_cb_dedup
    
    UNION
    
    -- Toko dari Realisasi Transaksi/IR (jika ada yang tidak terdaftar di CB)
    SELECT DISTINCT 
        distributor_id, sls_id, outlet_id, year, period, group_channel_id AS channel_id, salesforce_id,
        0 AS is_cb_active
    FROM {{ ref('gold_grading_dashboard') }}
)

-- MAIN FLAT MODEL SUMMARY
SELECT 
    COALESCE(act.year, o.year) AS year,
    COALESCE(act.period, o.period) AS period,
    COALESCE(act.week, 0) AS week,
    act.report_date,
    
    -- HIERARKI PENJUALAN M3
    ah.sd_id, ah.sd_nm,
    ah.nsm_id, ah.nsm_nm,
    ah.grsm_id, ah.grsm_nm,
    ah.rsm_id, ah.rsm_nm,
    ah.ss_id, ah.ss_nm,
    o.sls_id, ah.sls_nm,
    o.distributor_id, ah.distributor_nm,
    o.outlet_id,
    
    -- SALESFORCE & CHANNEL
    COALESCE(act.salesforce_id, o.salesforce_id) AS salesforce_id,
    COALESCE(mgc.gsalesforce_id, 'UNMAPPED_GSALESFORCE') AS gsalesforce_id,
    COALESCE(mgc.gsalesforce_nm, 'OTHERS / UNMAPPED') AS gsalesforce_nm,
    COALESCE(mcs.group_channel_id, 'UNMAPPED_CHANNEL') AS group_channel_id,
    COALESCE(mcs.group_channel_nm, 'OTHERS / UNMAPPED') AS group_channel_nm,
    
    -- PRODUK & REALISASI (DARI FACT DETAIL)
    COALESCE(act.subbrand_id, 'NO_TRANSACTION') AS subbrand_id,
    COALESCE(act.subbrand_nm, 'NO TRANSACTION / UNVISITED') AS subbrand_nm,
    act.pcode,
    act.pcode_nm,
    act.grade,
    
    -- ANCHOR METRICS & METRIK REALISASI
    o.is_cb_active,
    COALESCE(tc.tgt_call_daily, 0) AS tgt_call_daily,
    COALESCE(act.inv_qty, 0) AS inv_qty,
    COALESCE(act.inv_val, 0) AS inv_val,
    COALESCE(act.facing_qty, 0) AS facing_qty,
    CASE WHEN act.outlet_id IS NOT NULL THEN 1 ELSE 0 END AS is_visited

FROM cte_all_outlets o

-- JOIN 1: HIERARKI PENJUALAN M3 AKTIF
JOIN active_hierarchy ah 
    ON o.distributor_id = ah.distributor_id 
   AND o.sls_id = ah.sls_id

-- JOIN 2: REALISASI TRANSAKSI SALES SFA & IR HARIAN PER ITEM
LEFT JOIN {{ ref('gold_grading_dashboard') }} act
    ON o.distributor_id = act.distributor_id
   AND o.outlet_id = act.outlet_id
   AND o.year = act.year
   AND o.period = act.period

-- JOIN 3: TARGET CALL HARIAN
LEFT JOIN cte_target_call tc
    ON o.distributor_id = tc.distributor_id
   AND o.sls_id = tc.sls_id
   AND act.report_date = tc.report_date

-- JOIN 4: MASTER MAPPING
LEFT JOIN raw_ficom_m3.m_mapping_group_salesforce mgc 
    ON COALESCE(act.salesforce_id, o.salesforce_id) = mgc.salesforce_id::varchar
LEFT JOIN raw_ficom_m3.m_group_channels mcs 
    ON o.channel_id = mcs.channel_id::varchar