{{
    config(
        schema='bift',
        materialized='table',
        alias='silver_oa_transaction_dev',
        unique_key=['distributor_id', 'sls_id', 'cust_id', 'tahun', 'periode', 'inv_no', 'pcode'],
        indexes=[
          {'columns': ['tahun', 'periode', 'distributor_id', 'sls_id', 'cust_id'], 'type': 'btree'},
          {'columns': ['tahun', 'periode', 'week'],                              'type': 'btree'},
          {'columns': ['tahun', 'periode', 'pcode'],                              'type': 'btree'},
          {'columns': ['inv_date'],                                               'type': 'btree'},
          {'columns': ['distributor_id', 'sls_id', 'cust_id'],                    'type': 'btree'},
          {'columns': ['gdiv_id', 'source_schema'],                               'type': 'btree'}
        ]
    )
}}

WITH bronze_cb_distinct AS (
    {% for p in range(5, 6) %}
    SELECT DISTINCT ON (distributor_id, cust_id, tahun, periode)
        source_schema,
        tahun,
        periode,
        distributor_id,
        distributor_nm,
        cust_id,
        cust_nm,
        channel_id,
        channel_nm,
        group_channel_id,
        group_channel_nm,
        cycle_kunjungan,
        route,
        provinsi_code,
        provinsi_name,
        kabupaten_code,
        kabupaten_name,
        kecamatan_code,
        kecamatan_name,
        kelurahan_code,
        kelurahan_name,
        latitude,
        longitude
    FROM bift.bronze_cb
    WHERE tahun = 2026
      AND periode = {{ p }}
    {% if not loop.last %} UNION ALL {% endif %}
    {% endfor %}
),

vd AS (
    {% for w in range(18, 19) %}
    SELECT 
        v.subdist_id,
        v.custno,
        v.slsno,
        v.slsfc_id,
        v.prd_no AS periode,
        v."year" AS tahun,
        v.week_no,
        v.ord_date,
        v.inv_date,
        v.inv_no,
        v.pcode,
        v.inv_qty,
        v.inv_val,

        -- Sales Hierarchy details attached directly inside CTE
        COALESCE(sh.source_schema, 'm1') AS source_schema,
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
        COALESCE(sh.salesforce_id, v.slsfc_id) AS salesforce_id,
        sh.salesforce_nm,
        sh.salesforce_div_id,
        sh.salesforce_div_nm,
        sh.team_id,
        sh.opr_type
    FROM spx.vfsales_det v
    INNER JOIN bift.dim_salesman_hierarchy sh 
        ON v.subdist_id = sh.distributor_id
       AND v.slsno      = sh.sls_id
       AND (
            sh.termin_year IS NULL
            OR v."year" < sh.termin_year
            OR (v."year" = sh.termin_year AND v.prd_no <= sh.termin_period)
       )
    WHERE v.week_no = {{ w }}
      AND v.sts = '905'
      AND v.inv_val > 0
    {% if not loop.last %} UNION ALL {% endif %}
    {% endfor %}
)

SELECT 
    vd.source_schema,
    cb.tahun,
    cb.periode,
    vd.week_no::numeric AS week,
    vd.ord_date::date AS date,
    vd.inv_date::date AS inv_date,
    vd.gdiv_id,
    vd.gdiv_nm,
    vd.sd_id,
    vd.sd_nm,
    vd.nsm_id,
    vd.nsm_nm,
    vd.grsm_id,
    vd.grsm_nm,
    vd.rsm_id,
    vd.rsm_nm,
    vd.ss_id,
    vd.ss_nm,
    cb.distributor_id,
    COALESCE(vd.distributor_nm, cb.distributor_nm) AS distributor_nm,
    vd.slsno AS sls_id,
    vd.sls_nm,
    mmgs.gsalesforce1_id,
    mmgs.gsalesforce1_nm,
    mmgs.gsalesforce2_id,
    mmgs.gsalesforce2_nm,
    vd.salesforce_id,
    COALESCE(mmgs.salesforce_nm, vd.salesforce_nm) AS salesforce_nm,
    vd.salesforce_div_id,
    vd.salesforce_div_nm,
    vd.team_id,
    vd.opr_type,
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
    vd.inv_no,
    vd.pcode,
    f.pcode_nm,
    COALESCE(vd.inv_qty::numeric, 0) AS inv_qty,
    COALESCE(vd.inv_val::numeric, 0) AS inv_val,
    COALESCE(
        vd.inv_qty::numeric / NULLIF(f.conv_unit3, 0),
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
    f.sbu_nm,
    1 AS is_transaction
FROM vd
INNER JOIN bronze_cb_distinct cb 
    ON vd.subdist_id = cb.distributor_id
   AND vd.custno     = cb.cust_id
   AND vd.periode    = cb.periode
   AND vd.tahun      = cb.tahun
LEFT JOIN bift.dim_mapping_group_salesforce mmgs 
    ON vd.salesforce_id = mmgs.salesforce_id
   AND vd.source_schema = mmgs.source_schema
LEFT JOIN bift.dim_product f 
    ON vd.pcode = f.pcode
