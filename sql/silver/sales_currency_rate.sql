WITH cleaned AS (
    SELECT
        CAST("CurrencyRateID" AS INT)               AS currency_rate_id,
        CAST("CurrencyRateDate" AS DATE)            AS currency_rate_date,
        NULLIF(UPPER(TRIM("FromCurrencyCode")), '') AS from_currency_code,
        NULLIF(UPPER(TRIM("ToCurrencyCode")), '')   AS to_currency_code,
        CAST("AverageRate" AS DECIMAL(18,4))        AS average_rate,
        CAST("EndOfDayRate" AS DECIMAL(18,4))       AS end_of_day_rate,
        CAST("ModifiedDate" AS TIMESTAMP)           AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/SalesCurrencyRate.parquet')
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY currency_rate_id
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM cleaned
    WHERE currency_rate_id IS NOT NULL
)
SELECT
    currency_rate_id,
    currency_rate_date,
    from_currency_code,
    to_currency_code,
    average_rate,
    end_of_day_rate,
    modified_date,

    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;