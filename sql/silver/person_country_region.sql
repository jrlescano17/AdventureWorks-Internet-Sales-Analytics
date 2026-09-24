WITH cleaned AS (
    SELECT
        NULLIF(TRIM("CountryRegionCode"), '')   AS country_region_code,
        NULLIF(TRIM("Name"), '')                AS country_region_name,
        CAST("ModifiedDate" AS TIMESTAMP)       AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/PersonCountryRegion.parquet')
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY country_region_code
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM cleaned
    WHERE country_region_code IS NOT NULL
)
SELECT
    country_region_code,
    country_region_name,
    modified_date,

    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;