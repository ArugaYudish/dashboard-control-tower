{{
    config(
        schema='bift',
        materialized='table',
        alias='gold_npl_dashboard',
        pre_hook="SET LOCAL work_mem = '512MB';",
        indexes=[
          {'columns': ['tahun', 'periode'], 'type': 'btree'},
          {'columns': ['date'], 'type': 'btree'},

          {'columns': ['sd_id', 'nsm_id', 'rsm_id', 'ss_id', 'distributor_id'], 'type': 'btree'},
          {'columns': ['distributor_id', 'sls_id', 'cust_id'], 'type': 'btree'},

          {'columns': ['gsalesforce_id', 'salesforce_id'], 'type': 'btree'},
          {'columns': ['group_channel_id', 'channel_id'], 'type': 'btree'},
          {'columns': ['provinsi_code', 'kabupaten_code'], 'type': 'btree'}
        ]
    )
}}

WITH 

-- STEP 1: Enrich each transaction row (at inv_no + pcode grain) with tahun/periode
-- No grouping — every transaction line is preserved as-is
trx_with_period AS (
    SELECT
        s.subdist_id                AS distributor_id,
        s.slsno                     AS sls_id,
        s.custno                    AS cust_id,
        c."year"::numeric           AS tahun,
        c."period"::numeric         AS periode,
        c.week::numeric             AS week,
        s.ord_date::date            AS date,
        s.inv_no,
        s.pcode,
        s.inv_qty,
        s.inv_val
    FROM raw_ho.vfsales_det s
    -- Bridge: map daily ord_date -> tahun/periode via m_cycle3
    INNER JOIN spx.m_cycle3 c
            ON s.ord_date::date = c.cdate::date
    WHERE s.sts = '905'
)

SELECT

    -- 1. Period (from CB Cover grain)
    cs.tahun,
    cs.periode,

    -- 2. Date & Week (from transaction; NULL if no transaction)
    t.week,
    t.date,

    -- 3. Sales Hierarchy
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

    -- 4. Distributor
    sh.distributor_id,
    sh.distributor_nm,

    -- 5. Salesman & Salesforce
    sh.sls_id,
    sh.sls_nm,
    sh.salesforce_id,
    sh.salesforce_nm,
    sh.gsalesforce_id,
    sh.gsalesforce_nm,
    sh.salesforce_div_id,
    sh.salesforce_div_nm,
    sh.team_id,
    sh.opr_type,

    -- 6. Customer & Channel (from CB Cover)
    cs.cust_id,
    cs.cust_nm,
    cs.channel_id,
    cs.channel_nm,
    cs.group_channel_id,
    cs.group_channel_nm,

    -- 7. Visit Cycle (from CB Cover)
    cs.cycle_kunjungan,
    cs.route,

    -- 8. Location (from CB Cover — already enriched via dim_customer + dim_lokasi)
    cs.provinsi_code,
    cs.provinsi_name,
    cs.kabupaten_code,
    cs.kabupaten_name,
    cs.kecamatan_code,
    cs.kecamatan_name,
    cs.kelurahan_code,
    cs.kelurahan_name,
    cs.latitude,
    cs.longitude,

    -- 9. Transaction Detail (NULL when no transaction in this period)
    t.inv_no,
    t.pcode,
    t.inv_qty,
    t.inv_val,

    -- 10. CB & Transaction Flags
    1                               AS is_cb,  -- always 1 since CB Cover is the driving table
    CASE
        WHEN t.inv_no IS NOT NULL THEN 1
        ELSE 0
    END                             AS is_transaction

-- STEP A: CB Cover — outlets covered per tahun-periode
FROM bift.dim_salesman_hierarchy sh
INNER JOIN bift.dim_fcustsls_staging cs
        ON cs.distributor_id = sh.distributor_id
       AND cs.sls_id         = sh.sls_id

-- STEP B: Left join transaction rows (inv_no + pcode grain) matched via tahun-periode
--         Outlets with no transaction in this period remain as 1 row with NULL trx columns
LEFT JOIN trx_with_period t
       ON t.distributor_id   = cs.distributor_id
      AND t.sls_id           = cs.sls_id
      AND t.cust_id          = cs.cust_id
      AND t.tahun            = cs.tahun
      AND t.periode          = cs.periode