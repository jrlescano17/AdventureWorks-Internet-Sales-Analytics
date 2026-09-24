WITH cleaned AS (
    SELECT
        CAST("ProductCategoryID" AS INT)    AS product_category_id,
        NULLIF(TRIM("Name"), '')            AS product_category_name,
        CAST("ModifiedDate" AS TIMESTAMP)   AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/ProductionProductCategory.parquet')
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY product_category_id
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM cleaned
)
SELECT
    product_category_id,
    product_category_name,
    modified_date,
    
    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;