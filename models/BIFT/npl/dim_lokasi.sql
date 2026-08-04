{{
    config(
        schema='bift',
        materialized='table',
        alias='dim_lokasi',
        indexes=[
          {'columns': ['kelurahan_code'], 'type': 'btree'}
        ]
    )
}}

WITH kelurahan AS (
    SELECT
        t11,
        t12,
        t13,
        t14,
        ket,
        ROW_NUMBER() OVER (
            PARTITION BY t11, t12, t13, t14 
            ORDER BY _airbyte_extracted_at DESC
        ) AS rn
    FROM {{ source('raw_ho_mdm', 'fcshir14') }}
),

dim_kelurahan AS (
    SELECT
        t11,
        t12,
        t13,
        t14,
        ket
    FROM kelurahan
    WHERE rn = 1
),

kecamatan AS (
    SELECT
        t11,
        t12,
        t13,
        ket,
        ROW_NUMBER() OVER (
            PARTITION BY t11, t12, t13 
            ORDER BY _airbyte_extracted_at DESC
        ) AS rn
    FROM {{ source('raw_ho_mdm', 'fcshir13') }}
),

dim_kecamatan AS (
    SELECT
        t11,
        t12,
        t13,
        ket
    FROM kecamatan
    WHERE rn = 1
),

kabupaten AS (
    SELECT
        t11,
        t12,
        ket,
        ROW_NUMBER() OVER (
            PARTITION BY t11, t12 
            ORDER BY _airbyte_extracted_at DESC
        ) AS rn
    FROM {{ source('raw_ho_mdm', 'fcshir12') }}
),

dim_kabupaten AS (
    SELECT
        t11,
        t12,
        ket
    FROM kabupaten
    WHERE rn = 1
),

provinsi AS (
    SELECT
        t11,
        ket,
        ROW_NUMBER() OVER (
            PARTITION BY t11 
            ORDER BY _airbyte_extracted_at DESC
        ) AS rn
    FROM {{ source('raw_ho_mdm', 'fcshir11') }}
),

dim_provinsi AS (
    SELECT
        t11,
        ket
    FROM provinsi
    WHERE rn = 1
)

SELECT 
    -- Administrative Codes
    kl.t11 AS provinsi_code,
    kl.t12 AS kabupaten_code,
    kl.t13 AS kecamatan_code,
    kl.t14 AS kelurahan_code,
    
    -- Region Names
    p.ket  AS provinsi_name,
    kb.ket AS kabupaten_name,
    kc.ket AS kecamatan_name,
    kl.ket AS kelurahan_name

FROM dim_kelurahan kl

-- Join Kecamatan
LEFT JOIN dim_kecamatan kc
       ON kl.t11 = kc.t11
      AND kl.t12 = kc.t12
      AND kl.t13 = kc.t13

-- Join Kabupaten
LEFT JOIN dim_kabupaten kb
       ON kl.t11 = kb.t11
      AND kl.t12 = kb.t12

-- Join Provinsi
LEFT JOIN dim_provinsi p
       ON kl.t11 = p.t11

ORDER BY provinsi_code, kabupaten_code, kecamatan_code, kelurahan_code