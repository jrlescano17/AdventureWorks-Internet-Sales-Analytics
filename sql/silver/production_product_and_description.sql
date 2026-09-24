WITH cleaned AS (
    SELECT
        CAST("ProductID" AS INT)                AS product_id,
        NULLIF(TRIM("Name"), '')                AS product_name,
        NULLIF(TRIM("ProductModel"), '')        AS product_model,
        NULLIF(UPPER(TRIM("CultureID")), '')    AS culture_id,
        NULLIF(TRIM("Description"), '')         AS description,
        _ingestion_ts
    FROM read_parquet('data/bronze/ProductionvProductAndDescription.parquet')
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY product_id
            ORDER BY _ingestion_ts DESC
        ) AS rn
    FROM cleaned
    WHERE product_id IS NOT NULL
        AND culture_id = 'EN'
)
SELECT
    product_id,
    product_name,
    product_model,
    description,
    culture_id,
    
    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;