WITH override_purwosari_locations (purwosari_subdist, purwosari_plant) AS (
  VALUES ('103588', 'Purwosari'),
         ('117300', 'Purwosari'),
         ('176801', 'Purwosari'),
         ('176802', 'Purwosari'),
         ('185001', 'Purwosari')
),
calculated_t_sl_subdist AS (
  SELECT
    t.*,
    CASE WHEN t.reason IN ('F','G','S') THEN t.qty_bill ELSE t.so_awal END AS calculated_so_awal
  FROM spx.t_sl_subdist t
),
results AS (
  SELECT
    COALESCE(opl.purwosari_plant, mw.wh_nm) AS warehouse_name,
    mmsr.region_id AS region_code, mmsr.region_nm AS region_nm,
    mp.div_id || ' ' || md.div_nm AS division,
    COALESCE(mgd.division_name, 'HOMECARE') AS group_division,
    ma.acc_name AS sls_div,
    mmsr.region_id || ma.acc_name AS key1, vsh.grsm_name AS sales_group,
    ttss.plant, ttss.distributor_id AS subdist_id, mdist.distributor_nm, ttss.tgl_so,
    ttss.po_no AS so_no, ttss.ket_week, ttss.sku AS kdbarang, mp.pcodename AS nmbarang,
    ttss.so_awal, ttss.so_confirm, ttss.tgl_billing, ttss.bill_no, ttss.qty_bill, ttss.reason,
    ttss.calculated_so_awal,
    CASE WHEN ttss.reason IS NULL THEN 0 ELSE 1 END AS status_reason,
    CASE WHEN ttss.reason = 'o' AND ttss.qty_bill::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_o,
    CASE WHEN ttss.reason = 'M' AND ttss.qty_bill::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_m,
    CASE WHEN ttss.reason IN ('B','W') AND ttss.so_confirm::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_b,
    CASE WHEN ttss.reason = 'Z' AND ttss.so_confirm::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_z,
    CASE WHEN ttss.reason = 'd' AND ttss.so_confirm::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.so_confirm::numeric ELSE 0 END AS result_d,
    CASE WHEN ttss.reason = 'T' AND ttss.qty_bill::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_t,
    CASE WHEN ttss.reason = 'Y' AND ttss.qty_bill::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_y,
    CASE WHEN ttss.reason = 'A' AND ttss.so_confirm::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_a,
    CASE WHEN ttss.reason = 'P' AND ttss.so_confirm::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_p,
    CASE WHEN ttss.reason = 'C' AND ttss.so_confirm::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_c,
    CASE WHEN ttss.reason = 'F' AND ttss.so_confirm::numeric >= 0 THEN ttss.so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_f,
    CASE WHEN ttss.reason = 'G' AND ttss.so_confirm::numeric >= 0 THEN ttss.so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_g,
    CASE WHEN ttss.reason = 'K' AND ttss.so_confirm::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.so_confirm::numeric ELSE 0 END AS result_k,
    CASE WHEN ttss.reason = 'S' AND ttss.so_confirm::numeric >= 0 THEN ttss.so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_s,
    CASE WHEN ttss.reason = 'X' AND ttss.so_confirm::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_x,
    CASE WHEN ttss.reason = 'PPN' AND ttss.so_confirm::numeric >= 0 THEN ttss.so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_ppn,
    CASE WHEN ttss.reason = 'e' AND ttss.qty_bill::numeric >= 0 THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric ELSE 0 END AS result_e,
    CASE
	  WHEN ttss.so_confirm::numeric = 0 AND ttss.qty_bill::numeric = 0 AND (ttss.reason IS NULL OR ttss.reason = '')
	  THEN ttss.so_awal::numeric
	  WHEN (ttss.reason IS NULL OR ttss.reason = '') AND ttss.so_confirm::numeric > 0
	  THEN ttss.so_awal::numeric - ttss.so_confirm::numeric
	  ELSE 0
	END AS no_reason
  FROM calculated_t_sl_subdist ttss
  JOIN spx.m_product mp ON ttss.sku = mp.pcode
  JOIN spx.m_acc_div mad ON mp.div_id = mad.div_id
  JOIN spx.m_acc ma ON mad.acc_id = ma.acc_id
  LEFT JOIN override_purwosari_locations opl ON ttss.distributor_id = opl.purwosari_subdist
  LEFT JOIN spx.m_warehouse mw ON ttss.plant = mw.wh_id
  LEFT JOIN spx.m_mapping_subdist_region mmsr ON ttss.distributor_id = mmsr.distributor_id
  LEFT JOIN spx.m_division md ON mp.div_id = md.div_id
  LEFT JOIN spx.m_group_division mgd ON mgd.division_id = mp.div_id
  LEFT JOIN spx.v_sales_hierarchy vsh ON ttss.distributor_id = vsh.distributor_id
  LEFT JOIN spx.m_distributor mdist ON ttss.distributor_id = mdist.distributor_id
  WHERE ma.acc_id NOT IN ('AC0000', 'MT')
),
totals AS (
  SELECT
    r.*,
    (result_o + result_m + result_b + result_z + result_d + result_t +
     result_y + result_a + result_p + result_c + result_f + result_g +
     result_k + result_s + result_x + result_ppn) AS sum_z_ao
  FROM results r
)
SELECT
  t.warehouse_name, t.region_code, t.region_nm, t.division, t.group_division, t.sls_div, t.key1, t.sales_group, t.plant, 
  t.subdist_id, t.distributor_nm, t.tgl_so, t.so_no, t.ket_week, t.kdbarang, t.nmbarang, t.so_awal, t.so_confirm, 
  t.tgl_billing, t.bill_no, t.qty_bill, t.reason, t.calculated_so_awal, t.status_reason, t.result_o, t.result_m, 
  t.result_b, t.result_z, t.result_d, t.result_t, t.result_y, t.result_a, t.result_p, t.result_c, 
  t.result_f, t.result_g, t.result_k, t.result_s, t.result_x, t.result_ppn, t.result_e,
  CASE
    WHEN t.reason IN ('G','P','S','U')
      OR (t.calculated_so_awal::numeric - t.so_confirm::numeric - t.result_e - t.sum_z_ao) < 0
      OR (t.sum_z_ao + t.result_e) < 0
    THEN 0
    WHEN t.calculated_so_awal::numeric = 0 AND t.so_confirm::numeric = 0 AND (t.reason IS NULL OR t.reason = '')
    THEN -t.qty_bill::numeric
    WHEN t.calculated_so_awal::numeric <> t.so_confirm::numeric
    THEN t.so_confirm::numeric - t.qty_bill::numeric
    ELSE t.calculated_so_awal::numeric - t.qty_bill::numeric
  END AS late_bill,
  t.no_reason
FROM totals t