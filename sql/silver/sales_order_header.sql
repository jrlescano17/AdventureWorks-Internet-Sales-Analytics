WITH cleaned AS (
    SELECT
        CAST("SalesOrderID" AS INT)                     AS sales_order_id,
        CAST("RevisionNumber" AS TINYINT)               AS revision_number,
        CAST("OrderDate" AS DATE)                       AS order_date,
        CAST("DueDate" AS DATE)                         AS due_date,
        CAST("ShipDate" AS DATE)                        AS ship_date,
        CAST("Status" AS TINYINT)                       AS order_status,
        CAST("OnlineOrderFlag" AS BOOLEAN)              AS is_online_order,
        NULLIF(UPPER(TRIM("SalesOrderNumber")), '')     AS sales_order_number,
        NULLIF(UPPER(TRIM("PurchaseOrderNumber")), '')  AS purchase_order_number,
        NULLIF(UPPER(TRIM("AccountNumber")), '')        AS account_number,
        CAST("CustomerID" AS INT)                       AS customer_id,
        CAST("SalesPersonID" AS INT)                    AS sales_person_id,
        CAST("TerritoryID" AS INT)                      AS territory_id,
        CAST("BillToAddressID" AS INT)                  AS bill_to_address_id,
        CAST("ShipToAddressID" AS INT)                  AS ship_to_address_id,
        CAST("ShipMethodID" AS INT)                     AS ship_method_id,
        CAST("CreditCardID" AS INT)                     AS credit_card_id,
        NULLIF(TRIM("CreditCardApprovalCode"), '')      AS credit_card_approval_code,
        CAST("CurrencyRateID" AS INT)                   AS currency_rate_id,
        CAST("SubTotal" AS DECIMAL(18,4))               AS sub_total,
        CAST("TaxAmt" AS DECIMAL(18,4))                 AS tax_amount,
        CAST("Freight" AS DECIMAL(18,4))                AS freight,
        CAST("TotalDue" AS DECIMAL(18,4))               AS total_due,
        NULLIF(TRIM("Comment"), '')                     AS order_comment,
        CAST("ModifiedDate" AS TIMESTAMP)               AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/SalesSalesOrderHeader.parquet')
),
normalized AS (
    SELECT
        *,
        CASE
            WHEN order_status IS NULL THEN NULL
            WHEN order_status = 1     THEN 'In process'
            WHEN order_status = 2     THEN 'Approved'
            WHEN order_status = 3     THEN 'Backordered'
            WHEN order_status = 4     THEN 'Rejected'
            WHEN order_status = 5     THEN 'Shipped'
            WHEN order_status = 6     THEN 'Cancelled'
            ELSE 'Unknown'
        END AS status_desc
    FROM cleaned
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY sales_order_id
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM normalized
    WHERE sales_order_id IS NOT NULL
)
SELECT
    sales_order_id,
    revision_number,
    order_date,
    due_date,
    ship_date,
    order_status,
    status_desc,
    is_online_order,
    sales_order_number,
    purchase_order_number,
    account_number,
    customer_id,
    sales_person_id,
    territory_id,
    bill_to_address_id,
    ship_to_address_id,
    ship_method_id,
    credit_card_id,
    credit_card_approval_code,
    currency_rate_id,
    sub_total,
    tax_amount,
    freight,
    total_due,
    order_comment,
    modified_date,

    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1