WITH cleaned AS (
    SELECT
        CAST("ProductID" AS INT)                            AS product_id,
        NULLIF(TRIM("Name"), '')                            AS product_name,
        NULLIF(UPPER(TRIM("ProductNumber")), '')            AS product_number,
        CAST("MakeFlag" AS BOOLEAN)                         AS make_flag,
        CAST("FinishedGoodsFlag" AS BOOLEAN)                AS finished_goods_flag,
        NULLIF(TRIM("Color"), '')                           AS color,
        CAST("SafetyStockLevel" AS INT)                     AS safety_stock_level,
        CAST("ReorderPoint" AS INT)                         AS reorder_point,
        CAST("StandardCost" AS DECIMAL(18,4))               AS standard_cost,
        CAST("ListPrice" AS DECIMAL(18,4))                  AS list_price,
        NULLIF(UPPER(TRIM("Size")), '')                     AS product_size,
        NULLIF(UPPER(TRIM("SizeUnitMeasureCode")), '')      AS size_unit_measure_code,
        NULLIF(UPPER(TRIM("WeightUnitMeasureCode")), '')    AS weight_unit_measure_code,
        CAST("Weight" AS DECIMAL(18,4))                     AS product_weight,
        CAST("DaysToManufacture" AS INT)                    AS days_to_manufacture,
        NULLIF(UPPER(TRIM("ProductLine")), '')              AS product_line,
        NULLIF(UPPER(TRIM("Class")), '')                    AS product_class,
        NULLIF(UPPER(TRIM("Style")), '')                    AS product_style,
        CAST("ProductSubcategoryID" AS INT)                 AS product_subcategory_id,
        CAST("SellStartDate" AS DATE)                       AS sell_start_date,
        CAST("SellEndDate" AS DATE)                         AS sell_end_date,
        CAST("DiscontinuedDate" AS DATE)                    AS discontinued_date,
        CAST("ModifiedDate" AS TIMESTAMP)                   AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/ProductionProduct.parquet')
),
normalized AS (
    SELECT
        *,
        CASE
            WHEN make_flag = false  THEN 'Purchased'
            WHEN make_flag = true   THEN 'Manufactured in-house'
            ELSE NULL
        END AS make_desc,
        
        CASE
            WHEN finished_goods_flag = false    THEN 'Not salable'
            WHEN finished_goods_flag = true     THEN 'Salable'
            ELSE NULL
        END AS finished_goods_desc,

        CASE
            WHEN product_line = 'R' THEN 'Road'
            WHEN product_line = 'M' THEN 'Mountain'
            WHEN product_line = 'T' THEN 'Touring'
            WHEN product_line = 'S' THEN 'Standard'
            ELSE NULL
        END AS product_line_desc,

        CASE
            WHEN product_class = 'H' THEN 'High'
            WHEN product_class = 'M' THEN 'Medium'
            WHEN product_class = 'L' THEN 'Low'
            ELSE NULL
        END AS product_class_desc,

        CASE
            WHEN product_style = 'W' THEN 'Womens'
            WHEN product_style = 'M' THEN 'Mens'
            WHEN product_style = 'U' THEN 'Universal'
            ELSE NULL
        END AS product_style_desc,

        discontinued_date IS NOT NULL AS is_discontinued
    FROM cleaned
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY product_id
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM normalized
    WHERE product_id IS NOT NULL
)
SELECT
    product_id,
    product_name,
    product_number,
    make_flag,
    make_desc,
    finished_goods_flag,
    finished_goods_desc,
    color,
    safety_stock_level,
    reorder_point,
    standard_cost,
    list_price,
    product_size,
    size_unit_measure_code,
    weight_unit_measure_code,
    product_weight,
    days_to_manufacture,
    product_line,
    product_line_desc,
    product_class,
    product_class_desc,
    product_style,
    product_style_desc,
    product_subcategory_id,
    sell_start_date,
    sell_end_date,
    discontinued_date,
    is_discontinued,
    modified_date,

    -- metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;