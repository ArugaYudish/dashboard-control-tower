{{
    config(
        schema='bift',
        materialized='incremental',
        alias='silver_oa_transaction',
        unique_key=['distributor_id', 'sls_id', 'cust_id', 'tahun', 'periode', 'inv_no', 'pcode'],
        incremental_strategy='delete_insert',
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

SELECT 
    cb.source_schema,
    cb.tahun,
    cb.periode,
    vd.week_no::numeric AS week,
    vd.ord_date::date AS date,
    vd.inv_date::date AS inv_date,
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
FROM (
    {% for w in range(18, 19) %}
    SELECT *
    FROM spx.vfsales_det
    WHERE week_no = {{ w }}
      AND sts = '905'
      AND inv_val > 0
    {% if not loop.last %} UNION ALL {% endif %}
    {% endfor %}
) vd
INNER JOIN bift.bronze_cb cb 
    ON vd.subdist_id = cb.distributor_id
   AND vd.slsno      = cb.sls_id
   AND vd.custno     = cb.cust_id
   AND vd.prd_no     = cb.periode
   AND vd."year"     = cb.tahun
LEFT JOIN bift.dim_product f 
    ON vd.pcode = f.pcode
WHERE cb.tahun = 2026
