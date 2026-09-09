{{
    config(
        materialized='view',
        alias='v_last_update_integrasi'
    )
}}

-- Last Update per (sumber, year, week) untuk dashboard SCCT.
--
-- Sumbernya spx.t_bi_integration_watermark, yang diisi post-hook di
-- silver_sales_performance_parent lewat macro refresh_integration_watermark. Tabel itu
-- dibuat di on-run-start dan bukan model dbt, jadi tidak bisa di-ref().
--
-- Chart Superset memakainya dalam bentuk agregat tanpa GROUP BY, supaya query selalu
-- mengembalikan tepat satu baris dan '-' muncul otomatis untuk week yang belum ada
-- datanya:
--
--   select coalesce(max(last_update_text), '-') as last_update
--   from spx.v_last_update_integrasi
--   where source_code = 'STM'
--     and year = {{ "{{ url_param('year') }}" }}::int
--     and week = {{ "{{ url_param('week') }}" }}::int

select source_code,
       year,
       week,
       last_loaded_at,
       first_loaded_at,
       -- NULL untuk STA dan STOCK: relasi sumbernya memang tidak punya kolom timestamp.
       -- Hanya untuk diagnosa -- membedakan telat di-upload di Snopix vs telat sampai di BI.
       src_last_upload_at,
       row_count,
       to_char(last_loaded_at, 'DD/MM/YYYY HH24:MI') as last_update_text
from spx.t_bi_integration_watermark
