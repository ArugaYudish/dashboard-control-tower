-- dbt akan otomatis men-generate query ini menjadi VIEW atau TABLE di Postgres
{{ config(materialized='table') }}

SELECT 
    current_date AS tanggal_kalkulasi,
    COUNT(*) AS total_baris_sample
-- Ganti 'nama_tabel_kamu_yang_ada_di_spx' dengan tabel riil di database kamu jika ingin tes data riil
-- Kalau cuma mau dummy test, bisa pakai: SELECT 1 as id
