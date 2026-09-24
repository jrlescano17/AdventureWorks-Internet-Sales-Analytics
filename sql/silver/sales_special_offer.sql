WITH cleaned AS (
    SELECT
        CAST("SpecialOfferID" AS INT)           AS special_offer_id,
        NULLIF(TRIM("Description"), '')         AS description,
        CAST("DiscountPct" AS DECIMAL(18,4))    AS discount_pct,
        NULLIF(TRIM("Type"), '')                AS type,
        NULLIF(TRIM("Category"), '')            AS category,
        CAST("StartDate" AS DATE)               AS start_date,
        CAST("EndDate" AS DATE)                 AS end_date,
        CAST("MinQty" AS SMALLINT)              AS min_qty,
        CAST("MaxQty" AS SMALLINT)              AS max_qty,
        CAST("ModifiedDate" AS TIMESTAMP)       AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/SalesSpecialOffer.parquet')
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY special_offer_id
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM cleaned
    WHERE special_offer_id IS NOT NULL
)
SELECT
    special_offer_id,
    description,
    discount_pct,
    type,
    category,
    start_date,
    end_date,
    min_qty,
    max_qty,
    modified_date,

    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;