WITH cte_cities AS (
    SELECT
        city,
        state_province_id,
        postal_code,
        ROW_NUMBER() OVER (PARTITION BY postal_code, city, state_province_id ORDER BY city) AS fila
    FROM read_parquet('data/silver/person_address.parquet')
)

SELECT
    -1 AS geography_key,
    -1 AS sales_territory_key,
    'Unknown' AS city,
    NULL AS state_province_code,
    'Unknown' AS state_province_name,
    NULL AS country_region_code,
    'Unknown' AS country_region_name,
    NULL AS postal_code,
    NULL AS _hash,
    CURRENT_TIMESTAMP AS _insert_ts,
    CURRENT_TIMESTAMP AS _update_ts

UNION ALL

SELECT
    ROW_NUMBER() OVER (
        ORDER BY cr.country_region_code, sp.state_province_code, c.city, c.postal_code
    ) AS geography_key,

    COALESCE(dim.territory_key, -1) AS sales_territory_key,
    c.city,
    sp.state_province_code,
    sp.state_province_name,
    cr.country_region_code,
    cr.country_region_name,
    c.postal_code,
    

    unhex(sha256(
        CONCAT_WS('||',
            COALESCE(sp.state_province_name, ''),
            COALESCE(cr.country_region_name, ''),
            CAST(COALESCE(dim.territory_key, -1) AS VARCHAR)
        )
    )) AS _hash,

    CURRENT_TIMESTAMP AS _insert_ts,
    CURRENT_TIMESTAMP AS _update_ts


FROM cte_cities c
LEFT JOIN read_parquet('data/silver/person_state_province.parquet') sp  ON c.state_province_id = sp.state_province_id
LEFT JOIN read_parquet('data/silver/person_country_region.parquet') cr  ON sp.country_region_code = cr.country_region_code
LEFT JOIN read_parquet('data/gold/dim_sales_territory.parquet') dim     ON sp.territory_id = dim.territory_alternate_key
WHERE fila = 1;