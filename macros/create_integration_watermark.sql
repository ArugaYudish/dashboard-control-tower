{# Tabel watermark integrasi: mencatat kapan data tiap (sumber, year, week) masuk ke
   Snopix BI. Sengaja TIDAK dibuat sebagai model dbt -- dbt drop+create tabel setiap
   build, sedangkan isi tabel ini adalah riwayat, bukan turunan. Sekali sebuah week
   terkunci, nilainya harus bertahan lintas build selamanya.

   Dipanggil dari on-run-start di dbt_project.yml, jadi tabelnya dijamin ada sebelum
   model mana pun jalan. `if not exists` membuatnya idempoten. #}

{% macro create_integration_watermark() %}

create table if not exists spx.t_bi_integration_watermark (
    source_code        varchar(20) not null,   -- 'STM' | 'STA' | 'STOCK'
    year               int         not null,
    week               int         not null,
    row_count          bigint      not null,   -- diagnosa: berapa baris sumber saat dikunci
    src_last_upload_at timestamp   null,       -- max(upload_date) dari sisi Snopix; NULL utk STA/STOCK
    first_loaded_at    timestamp   not null,   -- pertama kali week ini terlihat di BI
    last_loaded_at     timestamp   not null,   -- yang ditampilkan ke user
    constraint t_bi_integration_watermark_pk primary key (source_code, year, week)
);

create index if not exists ix_biw_yw
    on spx.t_bi_integration_watermark (year, week);

{% endmacro %}
