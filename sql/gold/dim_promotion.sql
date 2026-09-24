SELECT
    -1 AS promotion_key,
    -1 AS promotion_alternate_key,
    'Unknown' AS promotion_name,
    NULL AS discount_pct,
    'Unknown' AS promotion_type,
    'Unknown' AS promotion_category,
    NULL AS start_date,
    NULL AS end_date,
    NULL AS min_quantity,
    NULL AS max_quantity,
    NULL AS _hash,
    CURRENT_TIMESTAMP AS _insert_ts,
    CURRENT_TIMESTAMP AS _update_ts

UNION ALL

SELECT
    ROW_NUMBER() OVER (
        ORDER BY special_offer_id
    ) AS promotion_key,

    special_offer_id    AS promotion_id,
    description         AS promotion_name,
    discount_pct,
    type                AS promotion_type,
    category            AS promotion_category,
    start_date,
    end_date,
    min_qty             AS min_quantity,
    max_qty             AS max_quantity,

    unhex(sha256(
        concat_ws('||',
            COALESCE(description, ''),
            COALESCE(CAST(discount_pct AS VARCHAR), ''),
            COALESCE(type, ''),
            COALESCE(category, ''),
            COALESCE(CAST(start_date AS VARCHAR), ''),
            COALESCE(CAST(end_date AS VARCHAR), ''),
            COALESCE(CAST(min_qty AS VARCHAR), ''),
            COALESCE(CAST(max_qty AS VARCHAR), '')
        )
    )) AS _hash,

    CURRENT_TIMESTAMP AS _insert_ts,
    CURRENT_TIMESTAMP AS _update_ts

FROM read_parquet(
    'data/silver/sales_special_offer.parquet'
)