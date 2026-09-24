SELECT
    -1 AS currency_key,
    '-1' AS currency_alternate_key,
    'Unknown' AS currency_name,
    NULL AS _hash,
    CURRENT_TIMESTAMP AS _insert_ts,
    CURRENT_TIMESTAMP AS _update_ts

UNION ALL

SELECT
    ROW_NUMBER() OVER (
        ORDER BY currency_code
    ) AS currency_key,

    currency_code AS currency_alternate_key,
    currency_name,

    unhex(sha256(
        concat_ws('||',
            coalesce(currency_code, ''),
            coalesce(currency_name, '')
        )
    )) AS _hash,

    CURRENT_TIMESTAMP AS _insert_ts,
    CURRENT_TIMESTAMP AS _update_ts

FROM read_parquet(
    'data/silver/sales_currency.parquet'
)