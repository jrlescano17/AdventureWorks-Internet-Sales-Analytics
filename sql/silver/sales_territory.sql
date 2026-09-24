WITH cleaned AS (
    SELECT
        CAST("TerritoryID" AS INT)                  AS territory_id,
        NULLIF(TRIM("Name"), '')                    AS territory_name,
        NULLIF(UPPER(TRIM("CountryRegionCode")), '') AS country_region_code,
        NULLIF(TRIM("Group"), '')                   AS territory_group,
        CAST("SalesYTD" AS DECIMAL(18,4))           AS sales_ytd,
        CAST("SalesLastYear" AS DECIMAL(18,4))      AS sales_last_year,
        CAST("CostYTD" AS DECIMAL(18,4))            AS cost_ytd,
        CAST("CostLastYear" AS DECIMAL(18,4))       AS cost_last_year,
        CAST("ModifiedDate" AS TIMESTAMP)           AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/SalesSalesTerritory.parquet')
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY territory_id
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM cleaned
    WHERE territory_id IS NOT NULL
)
SELECT
    territory_id,
    territory_name,
    country_region_code,
    territory_group,
    sales_ytd,
    sales_last_year,
    cost_ytd,
    cost_last_year,
    modified_date,

    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;