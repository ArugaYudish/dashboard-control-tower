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
	  WHEN ttss.reason IS NULL OR ttss.reason = '' THEN ''
	  WHEN ttss.reason = 'W' THEN 'B'
	  ELSE ttss.reason
	END AS new_reason,
    CASE
	  WHEN ttss.reason = 'U' AND ttss.so_confirm::numeric >= 0 
	  THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric
	  ELSE 0
	END AS result_u,
	CASE WHEN ttss.reason = 'W' AND ttss.so_confirm::numeric >= 0 
     THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric 
     ELSE 0 
	END AS result_w,
	CASE WHEN ttss.reason = 'B' AND ttss.so_confirm::numeric >= 0 
     THEN ttss.calculated_so_awal::numeric - ttss.qty_bill::numeric 
     ELSE 0 
	END AS result_b_dot,
    CASE
	  WHEN ttss.so_confirm::numeric = 0 AND ttss.qty_bill::numeric = 0 AND (ttss.reason IS NULL OR ttss.reason = '')
	  THEN ttss.so_awal::numeric
	  WHEN (ttss.reason IS NULL OR ttss.reason = '') AND ttss.so_confirm::numeric > 0
	  THEN ttss.so_awal::numeric - ttss.so_confirm::numeric
	  ELSE 0
	END AS no_reason,
	 CASE
	  WHEN SUBSTRING(ttss.ket_week FROM 9 FOR 3)  = 'SPK'
	    OR SUBSTRING(ttss.ket_week FROM 10 FOR 3) = 'SPK'
	    OR SUBSTRING(ttss.ket_week FROM 10 FOR 3) = 'STO'
	    OR SUBSTRING(ttss.ket_week FROM 9 FOR 3)  = 'STO'
	  THEN 'SPK'
	  WHEN SUBSTRING(ttss.ket_week FROM 9 FOR 6) = 'EX SPK' THEN 'SPK'
	  WHEN SUBSTRING(ttss.ket_week FROM 9 FOR 3) = 'SPO'    THEN 'SPO'
	  WHEN SUBSTRING(ttss.ket_week FROM 9 FOR 6) = 'EX FDO' THEN 'FDOS'
	  WHEN SUBSTRING(ttss.ket_week FROM 9 FOR 4) = 'FDOS'   THEN 'FDOS'
	  WHEN SUBSTRING(ttss.ket_week FROM 9 FOR 7) = 'PENG FD' THEN 'FDOS'
	  ELSE 'SPO'
	END AS calculated_keterangan_week
  FROM calculated_t_sl_subdist ttss
  JOIN spx.m_product mp ON ttss.sku = mp.pcode
  JOIN spx.m_acc_div mad ON mp.div_id = mad.div_id
  JOIN spx.m_acc ma ON mad.acc_id = ma.acc_id
  LEFT JOIN override_purwosari_locations opl ON ttss.distributor_id = opl.purwosari_subdist
  LEFT JOIN spx.m_warehouse mw ON ttss.plant = mw.wh_id
  LEFT JOIN spx.m_mapping_subdist_region mmsr ON ttss.distributor_id = mmsr.distributor_id
  LEFT JOIN spx.m_division md ON mp.div_id = md.div_id
  LEFT JOIN spx.m_group_division mgd ON mgd.division_id = mp.div_id
  LEFT JOIN spx.v_sales_hierarchy vsh ON ttss.distributor_id = vsh.distributor_id and ttss.sku = vsh.pcode
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
),
final_calc AS (
SELECT
  t.warehouse_name, t.region_code, t.region_nm, t.division, t.group_division, t.sls_div, t.key1, t.sales_group, t.plant, 
  t.subdist_id, t.distributor_nm, t.tgl_so, t.so_no, t.ket_week, t.kdbarang, t.nmbarang, t.so_awal, t.so_confirm, 
  t.tgl_billing, t.bill_no, t.qty_bill, t.reason, t.status_reason, t.result_o, t.result_m, 
  t.result_b, t.result_z, t.result_d, t.result_t, t.result_y, t.result_a, t.result_p, t.result_c, 
  t.result_f, t.result_g, t.result_k, t.result_s, t.result_x, t.result_ppn, t.result_e, t.sum_z_ao,
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
  t.no_reason,
CASE
  WHEN calculated_keterangan_week = 'SPK'  THEN 'SPK'
  WHEN calculated_keterangan_week = 'FDOS' THEN 'FDOS'
  ELSE 'SPO'
END AS calculated_keterangan,
t.calculated_keterangan_week,
t.new_reason,
t.result_u,
t.result_w,
t.result_b_dot,
t.result_e as result_e2,
t.calculated_so_awal,
CASE
  WHEN t.ket_week ~ '^[0-9]{2}\.' THEN LEFT(t.ket_week, 2)
  ELSE mc_so.week::text
END AS so_week,
CASE
  WHEN t.tgl_billing IS NULL OR t.tgl_billing IN ('', '00.00.0000') THEN 'Reason'
  ELSE mc_bill.week::text
END AS billing_week,
CASE
  WHEN t.tgl_billing IS NULL OR t.tgl_billing IN ('', '00.00.0000') THEN 'Reason'
  WHEN mc_bill.week - COALESCE(
         CASE WHEN t.ket_week ~ '^[0-9]{2}\.' THEN LEFT(t.ket_week, 2)::numeric END,
         mc_so.week
       ) < 1 THEN 'On Time'
  ELSE 'Not On Time'
END AS realisasi
FROM totals t
LEFT JOIN spx.m_cycle3 mc_bill
  ON mc_bill.cdate::date = TO_DATE(NULLIF(t.tgl_billing, '00.00.0000'), 'DD.MM.YYYY')
LEFT JOIN spx.m_cycle3 mc_so
  ON mc_so.cdate::date = TO_DATE(NULLIF(t.tgl_so, '00.00.0000'), 'DD.MM.YYYY')
)
SELECT
  fc.*,
  CASE WHEN fc.realisasi = 'On Time'     THEN fc.qty_bill::numeric ELSE 0 END AS qty_on_time,
  CASE WHEN fc.realisasi = 'Not On Time' THEN fc.qty_bill::numeric ELSE 0 END AS qty_not_on_time,
  CASE
    WHEN fc.realisasi = 'Reason'
    THEN fc.sum_z_ao + fc.result_w + fc.result_b_dot + fc.result_e2 - fc.result_b
    ELSE 0
  END AS qty_reason,
 CASE
  WHEN fc.tgl_billing IS NULL OR fc.tgl_billing IN ('', '00.00.0000') THEN ''
  ELSE CASE EXTRACT(DOW FROM TO_DATE(fc.tgl_billing, 'DD.MM.YYYY'))
    WHEN 0 THEN 'Minggu' WHEN 1 THEN 'Senin'  WHEN 2 THEN 'Selasa'
    WHEN 3 THEN 'Rabu'   WHEN 4 THEN 'Kamis'  WHEN 5 THEN 'Jumat'
    WHEN 6 THEN 'Sabtu'
  END
END AS billing_day,
CASE
  WHEN fc.tgl_so IS NULL OR fc.tgl_so IN ('', '00.00.0000') THEN ''
  ELSE CASE EXTRACT(DOW FROM TO_DATE(fc.tgl_so, 'DD.MM.YYYY'))
    WHEN 0 THEN 'Minggu' WHEN 1 THEN 'Senin'  WHEN 2 THEN 'Selasa'
    WHEN 3 THEN 'Rabu'   WHEN 4 THEN 'Kamis'  WHEN 5 THEN 'Jumat'
    WHEN 6 THEN 'Sabtu'
  END
END AS so_day,
CASE WHEN fc.calculated_keterangan = 'FDOS' THEN fc.calculated_so_awal::numeric ELSE 0 END AS so_awal_fdos,
CASE WHEN fc.calculated_keterangan = 'SPK' THEN fc.calculated_so_awal::numeric ELSE 0 END AS so_awal_spk,
CASE WHEN fc.calculated_keterangan = 'SPO' THEN fc.calculated_so_awal::numeric ELSE 0 END AS so_awal_spo
FROM final_calc fc