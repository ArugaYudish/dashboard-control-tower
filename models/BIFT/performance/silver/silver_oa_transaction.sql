{{
    config(
        schema='bift',
        materialized='table',
        alias='silver_oa_transaction',
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
        subdist_id,
        custno,
        slsno,
        slsfc_id,
        prd_no AS periode,
        "year" AS tahun,
        week_no,
        ord_date,
        inv_date,
        inv_no,
        pcode,
        inv_qty,
        inv_val
    FROM spx.vfsales_det
    WHERE week_no = {{ w }}
      AND sts = '905'
      AND inv_val > 0
    {% if not loop.last %} UNION ALL {% endif %}
    {% endfor %}
)

SELECT 
    COALESCE(sh.source_schema, cb.source_schema) AS source_schema,
    cb.tahun,
    cb.periode,
    vd.week_no::numeric AS week,
    vd.ord_date::date AS date,
    vd.inv_date::date AS inv_date,
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
    cb.distributor_id,
    COALESCE(sh.distributor_nm, cb.distributor_nm) AS distributor_nm,
    vd.slsno AS sls_id,
    sh.sls_nm,
    mmgs.gsalesforce1_id,
    mmgs.gsalesforce1_nm,
    mmgs.gsalesforce2_id,
    mmgs.gsalesforce2_nm,
    COALESCE(sh.salesforce_id, vd.slsfc_id) AS salesforce_id,
    COALESCE(mmgs.salesforce_nm, sh.salesforce_nm) AS salesforce_nm,
    sh.salesforce_div_id,
    sh.salesforce_div_nm,
    sh.team_id,
    sh.opr_type,
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
INNER JOIN bift.dim_salesman_hierarchy sh 
    ON vd.subdist_id = sh.distributor_id
   AND vd.slsno      = sh.sls_id
   AND (
        sh.termin_year IS NULL
        OR cb.tahun < sh.termin_year
        OR (cb.tahun = sh.termin_year AND cb.periode <= sh.termin_period)
   )
LEFT JOIN bift.dim_mapping_group_salesforce mmgs 
    ON sh.salesforce_id = mmgs.salesforce_id
   AND sh.source_schema = mmgs.source_schema
LEFT JOIN bift.dim_product f 
    ON vd.pcode = f.pcode
