WITH cleaned AS (
    SELECT
        CAST("CustomerID" AS INT)               AS customer_id,
        CAST("PersonID" AS INT)                 AS person_id,
        CAST("StoreID" AS INT)                  AS store_id,
        CAST("TerritoryID" AS INT)              AS territory_id,
        NULLIF(UPPER(TRIM("AccountNumber")), '') AS account_number,
        CAST("ModifiedDate" AS TIMESTAMP)       AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/SalesCustomer.parquet')
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM cleaned
    WHERE customer_id IS NOT NULL
)
SELECT
    customer_id,
    person_id,
    store_id,
    territory_id,
    account_number,
    modified_date,

    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;