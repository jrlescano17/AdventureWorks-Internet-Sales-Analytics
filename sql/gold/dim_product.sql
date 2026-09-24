WITH modeling AS (
    SELECT
        ROW_NUMBER() OVER (
            ORDER BY product_number
        ) AS product_key,

        p.product_number AS product_alternate_key,
        p.product_name,
        COALESCE(pd.product_model, 'Unknown') AS product_model,
        COALESCE(ps.product_subcategory_name, 'Unknown') AS product_subcategory,
        COALESCE(pc.product_category_name, 'Unknown') AS product_category,
        pd.description,
        p.weight_unit_measure_code,
        p.size_unit_measure_code,
        p.finished_goods_flag,
        p.finished_goods_desc,
        p.color,
        p.safety_stock_level,
        p.reorder_point,
        p.product_size,
        CASE
            WHEN p.product_size IS NULL                   THEN NULL
            WHEN p.product_size IN ('38', '40')           THEN '38-40 Cm'
            WHEN p.product_size IN ('42', '44', '46')     THEN '42-46 Cm'
            WHEN p.product_size IN ('48', '50', '52')     THEN '48-52 Cm'
            WHEN p.product_size IN ('54', '56', '58')     THEN '54-58 Cm'
            WHEN p.product_size IN ('60', '62')           THEN '60-62 Cm'
            WHEN p.product_size IN ('S', 'M', 'L', 'XL')  THEN p.product_size
            ELSE 'NA'
        END AS product_size_range,
        p.product_weight,
        p.days_to_manufacture,
        p.product_line,
        COALESCE(p.product_line_desc, 'Unknown') AS product_line_desc,
        p.product_class,
        COALESCE(p.product_class_desc, 'Unknown') AS product_class_desc,
        p.product_style,
        COALESCE(p.product_style_desc, 'Unknown') AS product_style_desc

    FROM read_parquet('data/silver/production_product.parquet') p
    LEFT JOIN read_parquet('data/silver/production_product_and_description.parquet') pd
        ON p.product_id = pd.product_id AND pd.culture_id = 'EN'
    LEFT JOIN read_parquet('data/silver/production_product_subcategory.parquet') ps
        ON p.product_subcategory_id = ps.product_subcategory_id
    LEFT JOIN read_parquet('data/silver/product_category.parquet') pc
        ON ps.product_category_id = pc.product_category_id
)

SELECT
    -1 AS product_key,
    '-1' AS product_alternate_key,
    'Unknown' AS product_name,
    'Unknown' AS product_model,
    'Unknown' AS product_subcategory,
    'Unknown' AS product_category,
    NULL AS description,
    NULL AS weight_unit_measure_code,
    NULL AS size_unit_measure_code,
    NULL AS finished_goods_flag,
    NULL AS finished_goods_desc,
    NULL AS color,
    NULL AS safety_stock_level,
    NULL AS reorder_point,
    NULL AS product_size,
    NULL AS product_size_range,
    NULL AS product_weight,
    NULL AS days_to_manufacture,
    NULL AS product_line,
    'Unknown' AS product_line_desc,
    NULL AS product_class,
    'Unknown' AS product_class_desc,
    NULL AS product_style,
    'Unknown' AS product_style_desc,
    NULL AS _hash,
    CURRENT_TIMESTAMP AS _insert_ts,
    CURRENT_TIMESTAMP AS _update_ts

UNION ALL

SELECT
    product_key,
    product_alternate_key,
    product_name,
    product_model,
    product_subcategory,
    product_category,
    description,
    weight_unit_measure_code,
    size_unit_measure_code,
    finished_goods_flag,
    finished_goods_desc,
    color,
    safety_stock_level,
    reorder_point,
    product_size,
    product_size_range,
    product_weight,
    days_to_manufacture,
    product_line,
    product_line_desc,
    product_class,
    product_class_desc,
    product_style,
    product_style_desc,

    unhex(sha256(
        concat_ws('||',
            COALESCE(product_name, ''),
            COALESCE(product_model, ''),
            COALESCE(product_subcategory, ''),
            COALESCE(product_category, ''),
            COALESCE(description, ''),
            COALESCE(weight_unit_measure_code, ''),
            COALESCE(size_unit_measure_code, ''),
            COALESCE(CAST(finished_goods_flag AS VARCHAR), ''),
            COALESCE(finished_goods_desc, ''),
            COALESCE(color, ''),
            COALESCE(CAST(safety_stock_level AS VARCHAR), ''),
            COALESCE(CAST(reorder_point AS VARCHAR), ''),
            COALESCE(product_size, ''),
            COALESCE(product_size_range, ''),
            COALESCE(CAST(product_weight AS VARCHAR), ''),
            COALESCE(CAST(days_to_manufacture AS VARCHAR), ''),
            COALESCE(product_line, ''),
            COALESCE(product_line_desc, ''),
            COALESCE(product_class, ''),
            COALESCE(product_class_desc, ''),
            COALESCE(product_style, ''),
            COALESCE(product_style_desc, '')
        )
    )) AS _hash,

    CURRENT_TIMESTAMP AS _insert_ts,
    CURRENT_TIMESTAMP AS _update_ts
FROM modeling