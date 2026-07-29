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

FROM raw_olap_m3.dim_kelurahan kl

-- Join Kecamatan
LEFT JOIN raw_olap_m3.dim_kecamatan kc
       ON kl.t11 = kc.t11
      AND kl.t12 = kc.t12
      AND kl.t13 = kc.t13

-- Join Kabupaten
LEFT JOIN raw_olap_m3.dim_kabupaten kb
       ON kl.t11 = kb.t11
      AND kl.t12 = kb.t12

-- Join Provinsi
LEFT JOIN raw_olap_m3.dim_provinsi p
       ON kl.t11 = p.t11

ORDER BY provinsi_code, kabupaten_code, kecamatan_code, kelurahan_code