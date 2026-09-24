WITH cleaned AS (
    SELECT
        CAST("AddressID" AS INT)                AS address_id,
        NULLIF(TRIM("AddressLine1"), '')        AS address_line1,
        NULLIF(TRIM("AddressLine2"), '')        AS address_line2,
        NULLIF(TRIM("City") , '')               AS city,
        CAST("StateProvinceID" AS INT)          AS state_province_id,
        NULLIF(UPPER(TRIM("PostalCode")), '')   AS postal_code,
        CAST("ModifiedDate" AS TIMESTAMP)       AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/PersonAddress.parquet')
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY address_id
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM cleaned
    WHERE address_id IS NOT NULL
)
SELECT
    address_id,
    address_line1,
    address_line2,
    city,
    state_province_id,
    postal_code,
    modified_date,

    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;