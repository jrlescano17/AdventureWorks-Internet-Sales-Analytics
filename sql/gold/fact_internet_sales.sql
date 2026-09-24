WITH base_lines AS (
    SELECT
        od.sales_order_id,
        od.sales_order_detail_id,
        p.product_number,
        oh.order_date,
        oh.due_date,
        oh.ship_date,
        cu.account_number AS customer_account,
        od.special_offer_id,
        COALESCE(c.to_currency_code, 'USD') AS currency_id,
        oh.territory_id,
        oh.sales_order_number,
        ROW_NUMBER() OVER (
            PARTITION BY oh.sales_order_id ORDER BY od.sales_order_detail_id
        ) AS sales_order_line_number,
        COUNT(*) OVER (PARTITION BY oh.sales_order_id) AS _max_line_number,
        oh.revision_number,
        od.order_quantity,
        od.unit_price,
        CAST(od.line_total AS DECIMAL(18,8)) AS line_total,
        od.unit_price_discount AS unit_price_discount_pct,
        od.order_quantity * od.unit_price * od.unit_price_discount AS discount_amount,
        pch.standard_cost AS product_standard_cost,
        od.order_quantity * pch.standard_cost AS total_product_cost,
        CAST(oh.sub_total AS DECIMAL(18,8)) AS _subtotal_header,
        CAST(oh.tax_amount AS DECIMAL(18,8)) AS _tax_header,
        CAST(oh.freight AS DECIMAL(18,8)) AS _freight_header,
        SUM(CAST(od.line_total AS DECIMAL(18,8))) OVER (PARTITION BY oh.sales_order_id) AS _order_total,
        line_total / SUM(CAST(od.line_total AS DECIMAL(18,8))) OVER (PARTITION BY oh.sales_order_id) AS _line_proportion,
        od.carrier_tracking_number,
        oh.purchase_order_number AS customer_po_number,
        GREATEST(oh._transform_ts, od._transform_ts) AS dwh_transform_ts
    FROM read_parquet('data/silver/sales_order_header.parquet') oh
    LEFT JOIN read_parquet('data/silver/sales_order_detail.parquet') od
        ON oh.sales_order_id = od.sales_order_id
    LEFT JOIN read_parquet('data/silver/production_product_cost_history.parquet') pch
        ON od.product_id = pch.product_id
        AND ( (oh.order_date BETWEEN pch.start_date AND pch.end_date)
            OR (oh.order_date >= pch.start_date AND pch.end_date IS NULL) )
    LEFT JOIN read_parquet('data/silver/sales_currency_rate.parquet') c
        ON oh.currency_rate_id = c.currency_rate_id
    LEFT JOIN read_parquet('data/silver/production_product.parquet') p
        ON od.product_id = p.product_id
    LEFT JOIN read_parquet('data/silver/sales_customer.parquet') cu
        ON oh.customer_id = cu.customer_id
    WHERE oh.is_online_order = true
),
cte_fact AS (
    SELECT
        product_number,
        order_date,
        due_date,
        ship_date,
        customer_account,
        special_offer_id,
        currency_id,
        territory_id,
        sales_order_number,
        sales_order_line_number,
        _max_line_number,
        revision_number,
        order_quantity,
        unit_price,
        line_total,
        unit_price_discount_pct,
        discount_amount,
        product_standard_cost,
        total_product_cost,
        carrier_tracking_number,
        customer_po_number,
        dwh_transform_ts,
        /* cálculo de sales_amount con residuo en la última línea */
        CASE 
            WHEN sales_order_line_number = _max_line_number THEN 
                CAST(
                    _subtotal_header - 
                    COALESCE(
                        SUM(CAST(_line_proportion * _subtotal_header AS DECIMAL(18, 4))) OVER (
                            PARTITION BY sales_order_id
                            ORDER BY sales_order_detail_id
                            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                        ), 
                        0
                    )
                    AS DECIMAL(18, 4)
                )
            ELSE 
                CAST(_line_proportion * _subtotal_header AS DECIMAL(18, 4))
        END AS sales_amount,
        
        CASE 
            WHEN sales_order_line_number = _max_line_number THEN 
                CAST(
                    _tax_header - 
                    COALESCE(
                        SUM(CAST(_line_proportion * _tax_header AS DECIMAL(18, 4))) OVER (
                            PARTITION BY sales_order_id
                            ORDER BY sales_order_detail_id
                            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                        ), 
                        0
                    )
                    AS DECIMAL(18, 4)
                )
            ELSE 
                CAST(_line_proportion * _tax_header AS DECIMAL(18, 4))
        END AS tax_amount,
        
        CASE 
            WHEN sales_order_line_number = _max_line_number THEN 
                CAST(
                    _freight_header - 
                    COALESCE(
                        SUM(CAST(_line_proportion * _freight_header AS DECIMAL(18, 4))) OVER (
                            PARTITION BY sales_order_id
                            ORDER BY sales_order_detail_id
                            ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
                        ), 
                        0
                    )
                    AS DECIMAL(18, 4)
                )
            ELSE 
                CAST(_line_proportion * _freight_header AS DECIMAL(18, 4))
        END AS freight

    FROM base_lines
)
SELECT
    COALESCE(prod.product_key, -1) AS product_key,
    CAST(strftime(fact.order_date, '%Y%m%d') AS INTEGER) AS order_date_key,
    CAST(strftime(fact.due_date, '%Y%m%d') AS INTEGER) AS due_date_key,
    CAST(strftime(fact.ship_date, '%Y%m%d') AS INTEGER) AS ship_date_key,
    COALESCE(cust.customer_key, -1) AS customer_key,
    COALESCE(prom.promotion_key, -1) AS promotion_key,
    COALESCE(curr.currency_key, -1) AS currency_key,
    COALESCE(terr.territory_key, -1) AS territory_key,
    fact.sales_order_number,
    fact.sales_order_line_number,
    fact.revision_number,
    fact.order_quantity,
    fact.unit_price,
    fact.line_total AS extended_amount,
    fact.unit_price_discount_pct,
    fact.discount_amount,
    fact.product_standard_cost,
    fact.total_product_cost,
    fact.sales_amount,
    fact.tax_amount,
    fact.freight,
    fact.carrier_tracking_number,
    fact.customer_po_number,
    CAST(fact.order_date AS DATE) AS order_date,
    CAST(fact.due_date AS DATE) AS due_date,
    CAST(fact.ship_date AS DATE) AS ship_date,

    unhex(sha256(
        concat_ws('||',
                COALESCE(CAST(prod.product_key AS VARCHAR), '-1'),
                COALESCE(CAST(strftime(fact.order_date, '%Y%m%d') AS VARCHAR), ''),
                COALESCE(CAST(strftime(fact.due_date, '%Y%m%d') AS VARCHAR), ''),
                COALESCE(CAST(strftime(fact.ship_date, '%Y%m%d') AS VARCHAR), ''),
                COALESCE(CAST(cust.customer_key AS VARCHAR), '-1'),
                COALESCE(CAST(prom.promotion_key AS VARCHAR), '-1'),
                COALESCE(CAST(curr.currency_key AS VARCHAR), '-1'),
                COALESCE(CAST(terr.territory_key AS VARCHAR), '-1'),

                COALESCE(fact.sales_order_number, ''),
                COALESCE(CAST(fact.sales_order_line_number AS VARCHAR), ''),
                COALESCE(CAST(fact.revision_number AS VARCHAR), ''),

                COALESCE(CAST(fact.order_quantity AS VARCHAR), ''),
                COALESCE(CAST(fact.unit_price AS VARCHAR), ''),
                COALESCE(CAST(fact.line_total AS VARCHAR), ''),
                COALESCE(CAST(fact.unit_price_discount_pct AS VARCHAR), ''),
                COALESCE(CAST(fact.discount_amount AS VARCHAR), ''),
                COALESCE(CAST(fact.product_standard_cost AS VARCHAR), ''),
                COALESCE(CAST(fact.total_product_cost AS VARCHAR), ''),
                COALESCE(CAST(fact.sales_amount AS VARCHAR), ''),
                COALESCE(CAST(fact.tax_amount AS VARCHAR), ''),
                COALESCE(CAST(fact.freight AS VARCHAR), ''),

                COALESCE(fact.carrier_tracking_number, ''),
                COALESCE(fact.customer_po_number, '')
        )
    )) AS _hash,

    CURRENT_TIMESTAMP AS _insert_ts,
    CURRENT_TIMESTAMP AS _update_ts


FROM cte_fact fact

LEFT JOIN read_parquet('data/gold/dim_product.parquet') prod
    ON fact.product_number = prod.product_alternate_key

LEFT JOIN read_parquet('data/gold/dim_customer.parquet') cust
    ON fact.customer_account = cust.customer_alternate_key

LEFT JOIN read_parquet('data/gold/dim_currency.parquet') curr
    ON fact.currency_id = curr.currency_alternate_key

LEFT JOIN read_parquet('data/gold/dim_promotion.parquet') prom
    ON fact.special_offer_id = prom.promotion_alternate_key

LEFT JOIN read_parquet('data/gold/dim_sales_territory.parquet') terr
    ON fact.territory_id = terr.territory_alternate_key