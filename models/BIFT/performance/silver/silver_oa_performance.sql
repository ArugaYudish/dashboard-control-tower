{{
    config(
        schema='bift',
        materialized='table',
        alias='silver_oa_performance',
        indexes=[
          {'columns': ['tahun', 'periode', 'distributor_id'],         'type': 'btree'},
          {'columns': ['tahun', 'periode', 'sls_id'],                 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'cust_id'],                'type': 'btree'},
          {'columns': ['tahun', 'periode', 'pcode'],                  'type': 'btree'},
          {'columns': ['distributor_id', 'sls_id', 'cust_id'],        'type': 'btree'},
          {'columns': ['gdiv_id', 'source_schema'],                   'type': 'btree'},
          {'columns': ['is_transaction'],                             'type': 'btree'}
        ]
    )
}}

WITH 
cb_cover AS (
    SELECT 
        cs.source_schema,
        cs.tahun,
        cs.periode,
        cs.distributor_id,
        cs.sls_id,
        cs.cust_id,
        cs.cust_nm,
        cs.channel_id,
        cs.channel_nm,
        cs.group_channel_id,
        cs.group_channel_nm,
        cs.cycle_kunjungan,
        cs.route,
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
        sh.gdiv_id,
        sh.gdiv_nm,
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
        sh.distributor_nm,
        sh.sls_nm,
        cs.gsalesforce1_id,
        cs.gsalesforce1_nm,
        cs.gsalesforce2_id,
        cs.gsalesforce2_nm,
        sh.salesforce_id,
        sh.salesforce_nm,
        sh.salesforce_div_id,
        sh.salesforce_div_nm,
        sh.team_id,
        sh.opr_type
    FROM bift.bronze_fcustsls_staging cs
    INNER JOIN bift.bronze_salesman_hierarchy sh 
        ON cs.distributor_id = sh.distributor_id
       AND cs.sls_id         = sh.sls_id
       AND cs.source_schema  = sh.source_schema
       -- Filter terminasi langsung di ON clause
       AND (
            sh.termin_year IS NULL
            OR cs.tahun < sh.termin_year
            OR (cs.tahun = sh.termin_year AND cs.periode <= sh.termin_period)
       )
),

-- ---------------------------------------------------------------------------
-- STEP 2 : Transactions — Index Scan Presisi Week 28 & 29 (6 - 19 Juli 2026)
-- ---------------------------------------------------------------------------
trx AS (
    SELECT 
        vd.subdist_id AS distributor_id,
        vd.slsno AS sls_id,
        vd.custno AS cust_id,
        2026::numeric AS tahun,
        7::numeric AS periode,
        vd.week_no::numeric AS week,
        vd.ord_date::date AS date,
        vd.inv_date::date AS inv_date,
        vd.inv_no AS inv_no,
        vd.pcode AS pcode,
        COALESCE(vd.inv_qty::numeric, 0) AS inv_qty,
        COALESCE(vd.inv_val::numeric, 0) AS inv_val,
        f.pcode_nm,
        COALESCE(
            vd.inv_qty::numeric / NULLIF(f.conv_unit2 * f.conv_unit3, 0),
            0
        ) AS qty_carton,
        f.gdiv_id AS product_gdiv_id,
        f.gdiv_nm AS product_gdiv_nm,
        f.div_id,
        f.div_nm,
        f.team_id AS product_team_id,
        f.team_nm AS product_team_nm,
        f.class_team_id,
        f.class_team_nm,
        f.subbrand_id,
        f.subbrand_nm,
        f.cat_id,
        f.cat_nm,
        f.sbu_id,
        f.sbu_nm
    FROM (
        {% for w in range(1, 6) %}
        SELECT *
        FROM spx.vfsales_det
        WHERE week_no = {{ w }}
        {% if not loop.last %}UNION ALL{% endif %}
        {% endfor %}
    ) vd
    LEFT JOIN bift.dim_product f 
        ON vd.pcode = f.pcode
),

-- ---------------------------------------------------------------------------
-- STEP 3A : Purchasing stream (Stream B - Transaksi SFA)
-- ---------------------------------------------------------------------------
trx_rows AS (
    SELECT 
        cb.source_schema,
        cb.tahun,
        cb.periode,
        trx.week,
        trx.date,
        trx.inv_date,
        cb.gdiv_id,
        cb.gdiv_nm,
        cb.sd_id,
        cb.sd_nm,
        cb.nsm_id,
        cb.nsm_nm,
        cb.grsm_id,
        cb.grsm_nm,
        cb.rsm_id,
        cb.rsm_nm,
        cb.ss_id,
        cb.ss_nm,
        cb.distributor_id,
        cb.distributor_nm,
        cb.sls_id,
        cb.sls_nm,
        cb.gsalesforce1_id,
        cb.gsalesforce1_nm,
        cb.gsalesforce2_id,
        cb.gsalesforce2_nm,
        cb.salesforce_id,
        cb.salesforce_nm,
        cb.salesforce_div_id,
        cb.salesforce_div_nm,
        cb.team_id,
        cb.opr_type,
        cb.cust_id,
        cb.cust_nm,
        cb.channel_id,
        cb.channel_nm,
        cb.group_channel_id,
        cb.group_channel_nm,
        cb.cycle_kunjungan,
        cb.route,
        cb.provinsi_code,
        cb.provinsi_name,
        cb.kabupaten_code,
        cb.kabupaten_name,
        cb.kecamatan_code,
        cb.kecamatan_name,
        cb.kelurahan_code,
        cb.kelurahan_name,
        cb.latitude,
        cb.longitude,
        trx.inv_no,
        trx.pcode,
        trx.pcode_nm,
        trx.inv_qty,
        trx.inv_val,
        trx.qty_carton,
        trx.product_gdiv_id,
        trx.product_gdiv_nm,
        trx.div_id,
        trx.div_nm,
        trx.product_team_id,
        trx.product_team_nm,
        trx.class_team_id,
        trx.class_team_nm,
        trx.subbrand_id,
        trx.subbrand_nm,
        trx.cat_id,
        trx.cat_nm,
        trx.sbu_id,
        trx.sbu_nm,
        1 AS is_transaction
    FROM cb_cover cb
    INNER JOIN trx 
        ON cb.distributor_id = trx.distributor_id
       AND cb.sls_id         = trx.sls_id
       AND cb.cust_id        = trx.cust_id
       AND cb.tahun          = trx.tahun
       AND cb.periode        = trx.periode
),

-- ---------------------------------------------------------------------------
-- STEP 3B : Master CB stream (Stream A - Universe Toko Pasif)
-- ---------------------------------------------------------------------------
non_purchasing_rows AS (
    SELECT 
        cb.source_schema,
        cb.tahun,
        cb.periode,
        0::numeric AS week,
        NULL::date AS date,
        NULL::date AS inv_date,
        cb.gdiv_id,
        cb.gdiv_nm,
        cb.sd_id,
        cb.sd_nm,
        cb.nsm_id,
        cb.nsm_nm,
        cb.grsm_id,
        cb.grsm_nm,
        cb.rsm_id,
        cb.rsm_nm,
        cb.ss_id,
        cb.ss_nm,
        cb.distributor_id,
        cb.distributor_nm,
        cb.sls_id,
        cb.sls_nm,
        cb.gsalesforce1_id,
        cb.gsalesforce1_nm,
        cb.gsalesforce2_id,
        cb.gsalesforce2_nm,
        cb.salesforce_id,
        cb.salesforce_nm,
        cb.salesforce_div_id,
        cb.salesforce_div_nm,
        cb.team_id,
        cb.opr_type,
        cb.cust_id,
        cb.cust_nm,
        cb.channel_id,
        cb.channel_nm,
        cb.group_channel_id,
        cb.group_channel_nm,
        cb.cycle_kunjungan,
        cb.route,
        cb.provinsi_code,
        cb.provinsi_name,
        cb.kabupaten_code,
        cb.kabupaten_name,
        cb.kecamatan_code,
        cb.kecamatan_name,
        cb.kelurahan_code,
        cb.kelurahan_name,
        cb.latitude,
        cb.longitude,
        '' AS inv_no,
        '' AS pcode,
        '' AS pcode_nm,
        0 AS inv_qty,
        0 AS inv_val,
        0 AS qty_carton,
        '' AS product_gdiv_id,
        '' AS product_gdiv_nm,
        '' AS div_id,
        '' AS div_nm,
        '' AS product_team_id,
        '' AS product_team_nm,
        '' AS class_team_id,
        '' AS class_team_nm,
        '' AS subbrand_id,
        '' AS subbrand_nm,
        '' AS cat_id,
        '' AS cat_nm,
        '' AS sbu_id,
        '' AS sbu_nm,
        0 AS is_transaction
    FROM cb_cover cb
)

SELECT * FROM trx_rows
UNION ALL
SELECT * FROM non_purchasing_rows