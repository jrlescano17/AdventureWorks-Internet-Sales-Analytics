WITH cleaned AS (
    SELECT
        CAST("SalesOrderID" AS INT)                     AS sales_order_id,
        CAST("SalesOrderDetailID" AS INT)               AS sales_order_detail_id,
        NULLIF(TRIM("CarrierTrackingNumber"), '')       AS carrier_tracking_number,
        CAST("OrderQty" AS INT)                         AS order_quantity,
        CAST("ProductID" AS INT)                        AS product_id,
        CAST("SpecialOfferID" AS INT)                   AS special_offer_id,
        CAST("UnitPrice" AS DECIMAL(18,4))              AS unit_price,
        CAST("UnitPriceDiscount" AS DECIMAL(18,4))      AS unit_price_discount,
        CAST("LineTotal" AS DECIMAL(18,4))              AS line_total,
        CAST("ModifiedDate" AS TIMESTAMP)               AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/SalesSalesOrderDetail.parquet')
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sales_order_detail_id
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM cleaned
    WHERE sales_order_detail_id IS NOT NULL
)
SELECT
    sales_order_id,
    sales_order_detail_id,
    carrier_tracking_number,
    order_quantity,
    product_id,
    special_offer_id,
    unit_price,
    unit_price_discount,
    line_total,
    modified_date,

    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;