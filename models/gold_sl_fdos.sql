{{ config(
    materialized='table',
    indexes=[
      {'columns': ['week', 'subdist_id', 'kdbarang']}
    ],
    pre_hook="SET LOCAL work_mem = '256MB'"
) }}


WITH override_purwosari_locations (purwosari_subdist, purwosari_plant) AS (
  VALUES ('103588', 'Purwosari'),
         ('117300', 'Purwosari'),
         ('176801', 'Purwosari'),
         ('176802', 'Purwosari'),
         ('185001', 'Purwosari')
),
-- so_awal / so_confirm / qty_bill sudah bertipe numeric di v_sl_subdist, dan
-- pembersihan pemisah ribuan ('1.700' -> 1700) dilakukan di view tersebut,
-- bukan di sini. Model ini cuma menyeragamkan NULL -> 0 supaya aritmatika
-- di bawah tidak menghasilkan NULL.
parsed_t_sl_subdist AS (
  SELECT
    t.*,
    COALESCE(t.so_awal, 0)    AS so_awal_num,
    COALESCE(t.so_confirm, 0) AS so_confirm_num,
    COALESCE(t.qty_bill, 0)   AS qty_bill_num,
    -- Kunci week untuk avg_last_3_week. `week` bisa bertipe text di sumber,
    -- jadi hanya nilai numerik yang dipakai; sisanya NULL dan tidak dihitung.
    CASE WHEN t.week::text ~ '^[0-9]+$' THEN t.week::text::int END AS week_num
  FROM spx.v_sl_subdist t
  -- Hanya ambil ket_week berformat 'XX.YYYY' (XX = minggu, YYYY = tahun),
  -- contoh '32.2026' atau '32.2026 SPK'. Pola wajib menyertakan tahun 4 digit
  -- supaya tanggal seperti '20.08.2026' tidak ikut lolos -- setelah '20.' isinya
  -- '08.2', bukan 4 digit. Batas [^0-9] di akhir mencegah '32.20261' ikut cocok.
  WHERE t.ket_week ~ '^[0-9]{2}\.[0-9]{4}([^0-9]|$)'
),
-- NOT MATERIALIZED: CTE ini dibaca dua cabang (detail + weekly_ratio). Tanpa
-- hint ini Postgres men-spool hasilnya ke disk dan mematikan parallel scan
-- untuk keduanya; dengan hint, tiap cabang men-scan sumbernya sendiri (murah,
-- karena filter ket_week sudah memangkas di level seq scan).
calculated_t_sl_subdist AS NOT MATERIALIZED (
  SELECT
    t.*,
    CASE WHEN t.reason IN ('F','G','S') THEN t.qty_bill_num ELSE t.so_awal_num END AS calculated_so_awal,
    -- Tahun kalender untuk week_num, diambil dari ket_week ('XX.YYYY' -- dijamin
    -- oleh filter di parsed_t_sl_subdist), dikoreksi kalau `week` ada di sisi
    -- lain pergantian tahun dibanding week SO-nya (SO '52.2026' yang ter-record
    -- di week 01 berarti tahun 2027, dan sebaliknya).
    CASE
      WHEN LEFT(t.ket_week, 2)::int >= 50 AND t.week_num <= 3
        THEN SUBSTRING(t.ket_week FROM 4 FOR 4)::int + 1
      WHEN LEFT(t.ket_week, 2)::int <= 3  AND t.week_num >= 50
        THEN SUBSTRING(t.ket_week FROM 4 FOR 4)::int - 1
      ELSE SUBSTRING(t.ket_week FROM 4 FOR 4)::int
    END AS week_year
  FROM parsed_t_sl_subdist t
),
-- m_cycle3 dipakai per tanggal billing. Di-dedupe per tanggal supaya (a) tidak
-- ada risiko baris fakta terduplikasi kalau satu cdate punya >1 row, dan (b)
-- planner tahu kuncinya unik -- tanpa ini estimasi join meledak jadi 50 juta
-- baris dan Postgres memilih merge join yang men-sort 565MB ke disk.
cycle_by_date AS (
  SELECT cdate::date AS cdate_d, MIN(week) AS week
  FROM spx.m_cycle3
  GROUP BY 1
),
reason as (
select reason_id, reason_nm, group_reason 
 from spx.m_reason
where type_id ='8'
),
results AS (
  SELECT
    COALESCE(opl.purwosari_plant, mw.wh_nm) AS warehouse_name,
    mdist.region_id AS region_code, mmsr.region_nm AS region_nm,
    mp.div_id || ' ' || md.div_nm AS division,
    COALESCE(mgd.division_name, 'HOMECARE') AS group_division,
    ma.acc_name AS sls_div,
    mmsr.region_id || ma.acc_name AS key1, vsh.grsm_name AS sales_group,
    ttss.plant, ttss.distributor_id AS subdist_id, mdist.distributor_nm, ttss.tgl_so,
    ttss.po_no AS so_no, ttss.ket_week, ttss.week, ttss.week_num, ttss.week_year,
    ttss.sku AS kdbarang, mp.pcodename AS nmbarang,
    mp.subbrand_id, msb.subbrand_nm,
    ttss.so_awal_num AS so_awal, ttss.so_confirm_num AS so_confirm, ttss.tgl_billing, ttss.bill_no,
    ttss.qty_bill_num AS qty_bill, ttss.reason,
    ttss.calculated_so_awal,
    CASE WHEN ttss.reason IS NULL THEN 0 ELSE 1 END AS status_reason,
    CASE WHEN ttss.reason = 'o' AND ttss.qty_bill_num >= 0 THEN ttss.calculated_so_awal - ttss.qty_bill_num ELSE 0 END AS result_o,
    CASE WHEN ttss.reason = 'M' AND ttss.qty_bill_num >= 0 THEN ttss.calculated_so_awal - ttss.qty_bill_num ELSE 0 END AS result_m,
    CASE WHEN ttss.reason IN ('B','W') AND ttss.so_confirm_num >= 0 THEN ttss.calculated_so_awal - ttss.qty_bill_num ELSE 0 END AS result_b,
    CASE WHEN ttss.reason = 'Z' AND ttss.so_confirm_num >= 0 THEN ttss.calculated_so_awal - ttss.qty_bill_num ELSE 0 END AS result_z,
    CASE WHEN ttss.reason = 'd' AND ttss.so_confirm_num >= 0 THEN ttss.calculated_so_awal - ttss.so_confirm_num ELSE 0 END AS result_d,
    CASE WHEN ttss.reason = 'T' AND ttss.qty_bill_num >= 0 THEN ttss.calculated_so_awal - ttss.qty_bill_num ELSE 0 END AS result_t,
    CASE WHEN ttss.reason = 'Y' AND ttss.qty_bill_num >= 0 THEN ttss.calculated_so_awal - ttss.qty_bill_num ELSE 0 END AS result_y,
    CASE WHEN ttss.reason = 'A' AND ttss.so_confirm_num >= 0 THEN ttss.calculated_so_awal - ttss.qty_bill_num ELSE 0 END AS result_a,
    CASE WHEN ttss.reason = 'P' AND ttss.so_confirm_num >= 0 THEN ttss.calculated_so_awal - ttss.qty_bill_num ELSE 0 END AS result_p,
    CASE WHEN ttss.reason = 'C' AND ttss.so_confirm_num >= 0 THEN ttss.calculated_so_awal - ttss.qty_bill_num ELSE 0 END AS result_c,
    CASE WHEN ttss.reason = 'F' AND ttss.so_confirm_num >= 0 THEN ttss.so_awal_num - ttss.qty_bill_num ELSE 0 END AS result_f,
    CASE WHEN ttss.reason = 'G' AND ttss.so_confirm_num >= 0 THEN ttss.so_awal_num - ttss.qty_bill_num ELSE 0 END AS result_g,
    CASE WHEN ttss.reason = 'K' AND ttss.so_confirm_num >= 0 THEN ttss.calculated_so_awal - ttss.so_confirm_num ELSE 0 END AS result_k,
    CASE WHEN ttss.reason = 'S' AND ttss.so_confirm_num >= 0 THEN ttss.so_awal_num - ttss.qty_bill_num ELSE 0 END AS result_s,
    CASE WHEN ttss.reason = 'X' AND ttss.so_confirm_num >= 0 THEN ttss.calculated_so_awal - ttss.qty_bill_num ELSE 0 END AS result_x,
    CASE WHEN ttss.reason = 'PPN' AND ttss.so_confirm_num >= 0 THEN ttss.so_awal_num - ttss.qty_bill_num ELSE 0 END AS result_ppn,
    CASE WHEN ttss.reason = 'e' AND ttss.qty_bill_num >= 0 THEN ttss.calculated_so_awal - ttss.qty_bill_num ELSE 0 END AS result_e,
    CASE
	  WHEN ttss.reason IS NULL OR ttss.reason = '' THEN ''
	  WHEN ttss.reason = 'W' THEN 'B'
	  ELSE ttss.reason
	END AS new_reason,
    CASE
	  WHEN ttss.reason = 'U' AND ttss.so_confirm_num >= 0
	  THEN ttss.calculated_so_awal - ttss.qty_bill_num
	  ELSE 0
	END AS result_u,
	CASE WHEN ttss.reason = 'W' AND ttss.so_confirm_num >= 0
     THEN ttss.calculated_so_awal - ttss.qty_bill_num
     ELSE 0
	END AS result_w,
	CASE WHEN ttss.reason = 'B' AND ttss.so_confirm_num >= 0
     THEN ttss.calculated_so_awal - ttss.qty_bill_num
     ELSE 0
	END AS result_b_dot,
    CASE
	  WHEN ttss.so_confirm_num = 0 AND ttss.qty_bill_num = 0 AND (ttss.reason IS NULL OR ttss.reason = '')
	  THEN ttss.so_awal_num
	  WHEN (ttss.reason IS NULL OR ttss.reason = '') AND ttss.so_confirm_num > 0
	  THEN ttss.so_awal_num - ttss.so_confirm_num
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
  -- PK m_subbrand = (brand_id, subbrand_id), jadi subbrand_id saja tidak unik --
  -- join wajib pakai dua kolom supaya tidak ketarik subbrand milik brand lain.
  LEFT JOIN spx.m_subbrand msb ON mp.brand_id = msb.brand_id AND mp.subbrand_id = msb.subbrand_id
  LEFT JOIN override_purwosari_locations opl ON ttss.distributor_id = opl.purwosari_subdist
  LEFT JOIN spx.m_warehouse mw ON ttss.plant = mw.wh_id
  LEFT JOIN spx.m_division md ON mp.div_id = md.div_id
  LEFT JOIN spx.m_group_division mgd ON mgd.division_id = mp.div_id
  LEFT JOIN spx.v_sales_hierarchy_product vsh ON ttss.distributor_id = vsh.distributor_id and ttss.sku = vsh.pcode
  LEFT JOIN spx.m_distributor mdist ON ttss.distributor_id = mdist.distributor_id
  LEFT JOIN spx.m_region2 mmsr ON mdist.region_id = mmsr.region_id
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
  t.subdist_id, t.distributor_nm, t.tgl_so, t.so_no, t.ket_week, t.week, t.week_num, t.week_year,
  t.kdbarang, t.nmbarang,
  t.subbrand_id, t.subbrand_nm, t.so_awal, t.so_confirm,
  t.tgl_billing, t.bill_no, t.qty_bill, t.reason, t.status_reason, t.result_o, t.result_m, 
  t.result_b, t.result_z, t.result_d, t.result_t, t.result_y, t.result_a, t.result_p, t.result_c, 
  t.result_f, t.result_g, t.result_k, t.result_s, t.result_x, t.result_ppn, t.result_e, t.sum_z_ao,
  CASE
    WHEN t.reason IN ('G','P','S','U')
      OR (t.calculated_so_awal - t.so_confirm - t.result_e - t.sum_z_ao) < 0
      OR (t.sum_z_ao + t.result_e) < 0
    THEN 0
    WHEN t.calculated_so_awal = 0 AND t.so_confirm = 0 AND (t.reason IS NULL OR t.reason = '')
    THEN -t.qty_bill
    WHEN t.calculated_so_awal <> t.so_confirm
    THEN t.so_confirm - t.qty_bill
    ELSE t.calculated_so_awal - t.qty_bill
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
-- ket_week sudah dijamin berformat 'XX.YYYY' oleh filter di parsed_t_sl_subdist,
-- jadi dua digit pertama selalu angka dan aman di-cast tanpa guard.
LEFT(t.ket_week, 2) AS so_week,
CASE
  WHEN t.tgl_billing IS NULL OR t.tgl_billing IN ('', '00.00.0000') THEN 'Reason'
  ELSE mc_bill.week::text
END AS billing_week,
CASE
  WHEN t.tgl_billing IS NULL OR t.tgl_billing IN ('', '00.00.0000') THEN 'Reason'
  WHEN mc_bill.week - LEFT(t.ket_week, 2)::numeric < 1 THEN 'On Time'
  ELSE 'Not On Time'
END AS realisasi,
msd.jalur, msd.region_2, msd.region_3
FROM totals t
LEFT JOIN cycle_by_date mc_bill
  ON mc_bill.cdate_d = TO_DATE(NULLIF(t.tgl_billing, '00.00.0000'), 'DD.MM.YYYY')
LEFT JOIN spx.mapping_subdist_delivery msd on t.subdist_id = msd.distributor_id and t.plant = msd.plant_id 
),
-- Kolom final_calc ditulis eksplisit (bukan fc.*) supaya `week` bisa ditaruh
-- paling kanan. Kalau menambah kolom baru di final_calc, tambahkan juga di sini.
final_output AS (
SELECT
  fc.warehouse_name, fc.region_code, fc.region_nm, fc.division, fc.group_division, fc.sls_div, fc.key1,
  fc.sales_group, fc.plant, fc.subdist_id, fc.distributor_nm, fc.tgl_so, fc.so_no, fc.ket_week,
  fc.kdbarang, fc.nmbarang, fc.subbrand_id, fc.subbrand_nm, fc.so_awal, fc.so_confirm,
  fc.tgl_billing, fc.bill_no, fc.qty_bill,
  fc.reason, fc.status_reason, fc.result_o, fc.result_m, fc.result_b, fc.result_z, fc.result_d,
  fc.result_t, fc.result_y, fc.result_a, fc.result_p, fc.result_c, fc.result_f, fc.result_g,
  fc.result_k, fc.result_s, fc.result_x, fc.result_ppn, fc.result_e, fc.sum_z_ao, fc.late_bill,
  fc.no_reason, fc.calculated_keterangan, fc.calculated_keterangan_week, fc.new_reason, fc.result_u,
  fc.result_w, fc.result_b_dot, fc.result_e2, fc.calculated_so_awal, fc.so_week, fc.billing_week,
  fc.realisasi, fc.jalur, fc.region_2, fc.region_3,
  CASE WHEN fc.realisasi = 'On Time'     THEN fc.qty_bill ELSE 0 END AS qty_on_time,
  CASE WHEN fc.realisasi = 'Not On Time' THEN fc.qty_bill ELSE 0 END AS qty_not_on_time,
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
CASE WHEN fc.calculated_keterangan = 'FDOS' THEN fc.calculated_so_awal ELSE 0 END AS so_awal_fdos,
CASE WHEN fc.calculated_keterangan = 'SPK' THEN fc.calculated_so_awal ELSE 0 END AS so_awal_spk,
CASE WHEN fc.calculated_keterangan = 'SPO' THEN fc.calculated_so_awal ELSE 0 END AS so_awal_spo, reason.group_reason,
fc.week, fc.week_num, fc.week_year
FROM final_calc fc
 left join reason on fc.reason = reason.reason_id
),
-- ============================================================================
-- avg_last_3_week: rata-rata rasio bill vs SO dari 3 week SEBELUM week baris
-- ini, dihitung per kombinasi week + subdist_id + kdbarang.
--
-- Aturan yang dipakai:
--   * Rasio per week memakai rumus pencapaian yang sama:
--     SUM(qty_bill) / SUM(so_awal_fdos + so_awal_spk + so_awal_spo) * 100.
--   * Pembagi rata-rata SELALU 3. Week yang tidak punya data, atau punya data
--     tapi SO awalnya 0, dihitung sebagai 0%. Jadi week 32 = (p31+p30+p29)/3
--     walaupun hanya week 31 yang ada datanya.
--   * Lookback mengikuti kalender lintas tahun: week 01 mengambil week 52, 51,
--     dan 50 tahun sebelumnya (lihat week_spine).
-- ============================================================================
-- Agregat mingguan dibaca langsung dari calculated_t_sl_subdist, BUKAN dari
-- final_output. final_output lebarnya ~1,7 KB per baris; kalau CTE itu dibaca
-- dua kali, Postgres men-spool ~3,4 GB ke disk dan CTE scan-nya sendiri makan
-- puluhan detik. Cabang ini hanya butuh 6 kolom.
--
-- Penyebutnya memakai calculated_so_awal karena so_awal_fdos + so_awal_spk +
-- so_awal_spo SELALU sama dengan calculated_so_awal: ketiganya berasal dari
-- calculated_keterangan yang nilainya pasti salah satu dari FDOS/SPK/SPO, dan
-- yang tidak terpilih bernilai 0.
--
-- JOIN m_product/m_acc_div/m_acc + filter acc_id diulang di sini supaya
-- himpunan barisnya sama persis dengan yang masuk ke final_output.
weekly_ratio AS (
  SELECT
    ttss.week_year,
    ttss.week_num,
    ttss.distributor_id AS subdist_id,
    ttss.sku            AS kdbarang,
    CASE
      WHEN SUM(ttss.calculated_so_awal) = 0 THEN 0
      ELSE ROUND(
        (SUM(ttss.qty_bill_num)::numeric / NULLIF(SUM(ttss.calculated_so_awal), 0)::numeric) * 100
      , 1)
    END AS pct_week
  FROM calculated_t_sl_subdist ttss
  JOIN spx.m_product mp  ON ttss.sku = mp.pcode
  JOIN spx.m_acc_div mad ON mp.div_id = mad.div_id
  JOIN spx.m_acc ma      ON mad.acc_id = ma.acc_id
  WHERE ttss.week_num IS NOT NULL
    AND ma.acc_id NOT IN ('AC0000', 'MT')
  GROUP BY 1, 2, 3, 4
),
-- Urutan week absolut dari week yang benar-benar ada di data. Nomor urut ini
-- yang jadi sumbu window, supaya week 01 bersebelahan dengan week 52 tahun
-- sebelumnya, bukan melompat ke week 04 di tahun yang sama.
week_spine AS (
  SELECT
    week_year,
    week_num,
    ROW_NUMBER() OVER (ORDER BY week_year, week_num) AS week_seq
  FROM (SELECT DISTINCT week_year, week_num FROM weekly_ratio) d
),
weekly_avg_last_3 AS (
  SELECT
    r.week_year,
    r.week_num,
    r.subdist_id,
    r.kdbarang,
    -- SUM (bukan AVG) lalu dibagi 3: week yang tidak muncul di window tidak
    -- menambah SUM, jadi otomatis terhitung 0% tanpa mengecilkan pembagi.
    -- RANGE dipakai (bukan ROWS) supaya jendela dihitung dari jarak week, jadi
    -- week yang kosong pada subdist + kdbarang ini tidak menggeser jendela ke
    -- week yang lebih jauh.
    ROUND(
      COALESCE(
        SUM(r.pct_week) OVER (
          PARTITION BY r.subdist_id, r.kdbarang
          ORDER BY s.week_seq
          RANGE BETWEEN 3 PRECEDING AND 1 PRECEDING
        ), 0
      ) / 3
    , 1) AS avg_last_3_week
  FROM weekly_ratio r
  JOIN week_spine s
    ON s.week_year = r.week_year
   AND s.week_num  = r.week_num
)
SELECT
  o.*,
  -- Baris tanpa pasangan (week non-numerik, atau subdist_id/kdbarang NULL)
  -- diperlakukan sama dengan "tidak ada history" -> 0.
  COALESCE(w.avg_last_3_week, 0) AS avg_last_3_week,
  d.sls_div as channel, v.ss_id, v.rsm_id, v.grsm_id, v.nsm_id,
  p.div_id as sbu_id, p.brand_id, p.parent_id
FROM final_output o
-- Semua kondisi memakai perbandingan kolom = kolom (bukan ekspresi dan bukan
-- IS NOT DISTINCT FROM) supaya planner bisa memilih hash join.
LEFT JOIN weekly_avg_last_3 w
  ON  w.week_year  = o.week_year
  AND w.week_num   = o.week_num
  AND w.subdist_id = o.subdist_id
  AND w.kdbarang   = o.kdbarang
left join spx.m_product p on o.kdbarang = p.pcode
	left join spx.m_distributor d on o.subdist_id = d.distributor_id
	left join spx.v_sales_hierarchy_product v on o.subdist_id = v.distributor_id and o.kdbarang = v.pcode
