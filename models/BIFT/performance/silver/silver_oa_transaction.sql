{%- set ns = namespace() -%}
{%- do bift_resolve_cycle_window(ns, relation_schema='bift', relation_name='silver_oa_transaction', default_lookback_weeks=2) -%}

{{
    config(
        schema='bift',
        materialized='incremental',
        alias='silver_oa_transaction',
        unique_key=['tahun', 'periode', 'week'],
        incremental_strategy='delete+insert',
        pre_hook=[
            "SET LOCAL work_mem = '256MB'",
            "{% if is_incremental() and var('all_periods', false) %} TRUNCATE TABLE {{ this }}; {% endif %}"
        ],
        indexes=[
          {'columns': ['tahun', 'periode', 'week'], 'type': 'btree'}
        ]
    )
}}

WITH bronze_cb_distinct AS (
    SELECT DISTINCT ON (tahun, periode, distributor_id, cust_id)
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
    FROM {{ ref('bronze_cb') }}
    {% if is_incremental() and ns.filter_periods and (ns.period_pairs | length) > 0 %}
    WHERE (tahun, periode) IN (
        {%- for pair in ns.period_pairs -%}
        ({{ pair[0] }}, {{ pair[1] }}){% if not loop.last %}, {% endif %}
        {%- endfor -%}
    )
    {% endif %}
    ORDER BY tahun, periode, distributor_id, cust_id
),

vd AS (
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
    FROM {{ ref('vfsales_det') }}
    WHERE sts = '905'
      AND inv_val > 0
    {% if is_incremental() and ns.filter_periods and (ns.week_pairs | length) > 0 %}
      AND ("year", week_no) IN (
          {%- for wp in ns.week_pairs -%}
          ({{ wp[0] }}, {{ wp[1] }}){% if not loop.last %}, {% endif %}
          {%- endfor -%}
      )
      AND ("year", prd_no, week_no) IN (
          {%- for ypw in ns.ypw_triples -%}
          ({{ ypw[0] }}, {{ ypw[1] }}, {{ ypw[2] }}){% if not loop.last %}, {% endif %}
          {%- endfor -%}
      )
    {% endif %}
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
LEFT JOIN {{ ref('dim_product') }} f 
    ON vd.pcode = f.pcode
LEFT JOIN {{ ref('dim_salesman_hierarchy') }} sh 
    ON vd.subdist_id = sh.distributor_id
   AND vd.slsno      = sh.sls_id
   AND (
        CASE 
            WHEN f.gdiv_id IN ('02', '04', '07', '10') THEN '10'
            ELSE f.gdiv_id
        END = sh.gdiv_id
   )
   AND (
        sh.termin_year IS NULL
        OR cb.tahun < sh.termin_year
        OR (cb.tahun = sh.termin_year AND cb.periode <= sh.termin_period)
   )
LEFT JOIN {{ ref('dim_mapping_group_salesforce') }} mmgs 
    ON sh.salesforce_id = mmgs.salesforce_id
   AND sh.source_schema = mmgs.source_schema
