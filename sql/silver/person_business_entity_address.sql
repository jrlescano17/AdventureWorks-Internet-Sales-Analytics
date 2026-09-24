WITH cleaned AS (
    SELECT
        CAST("BusinessEntityID" AS INT)     AS business_entity_id,
        CAST("AddressID" AS INT)            AS address_id,
        CAST("AddressTypeID" AS INT)        AS address_type_id,
        CAST("ModifiedDate" AS TIMESTAMP)   AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/PersonBusinessEntityAddress.parquet')
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY business_entity_id, address_id, address_type_id
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM cleaned
    WHERE business_entity_id IS NOT NULL
        AND address_id IS NOT NULL
        AND address_type_id IS NOT NULL
)
SELECT
    business_entity_id,
    address_id,
    address_type_id,
    modified_date,

    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;