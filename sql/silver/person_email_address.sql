WITH cleaned AS (
    SELECT
        CAST("BusinessEntityID" AS INT)         AS business_entity_id,
        CAST("EmailAddressID" AS INT)           AS email_address_id,
        NULLIF(LOWER(TRIM("EmailAddress")), '') AS email_address,
        CAST("ModifiedDate" AS TIMESTAMP)       AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/PersonEmailAddress.parquet')
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY business_entity_id, email_address_id
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM cleaned
    WHERE business_entity_id IS NOT NULL
        AND email_address_id IS NOT NULL
)
SELECT
    business_entity_id,
    email_address_id,
    email_address,
    modified_date,
    
    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;