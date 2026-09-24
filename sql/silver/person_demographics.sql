WITH cleaned AS (
    SELECT
        CAST("BusinessEntityID" AS INT)             AS business_entity_id,
        CAST("BirthDate" AS DATE)                   AS birth_date,
        NULLIF(UPPER(TRIM("MaritalStatus")), '')    AS marital_status,
        NULLIF(TRIM("YearlyIncome"), '')            AS yearly_income,
        NULLIF(UPPER(TRIM("Gender")), '')           AS gender,
        CAST("TotalChildren" AS INT)                AS total_children,
        CAST("NumberChildrenAtHome" AS INT)         AS number_children_at_home,
        NULLIF(TRIM("Education"), '')               AS education,
        NULLIF(TRIM("Occupation"), '')              AS occupation,
        CAST("HomeOwnerFlag" AS BOOLEAN)            AS home_owner_flag,
        CAST("NumberCarsOwned" AS INT)              AS number_cars_owned,
        _ingestion_ts
    FROM read_parquet('data/bronze/SalesvPersonDemographics.parquet')
),
normalized AS (
    SELECT
        *,
        CASE
            WHEN marital_status IS NULL THEN NULL
            WHEN marital_status = 'S' THEN 'Single'
            WHEN marital_status = 'M' THEN 'Married'
            ELSE 'Other'
        END AS marital_status_desc,
        CASE
            WHEN gender IS NULL THEN NULL
            WHEN gender = 'F' THEN 'Female'
            WHEN gender = 'M' THEN 'Male'
            ELSE 'Other'
        END AS gender_desc
    FROM cleaned
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY business_entity_id
            ORDER BY _ingestion_ts DESC
        ) AS rn
    FROM normalized
    WHERE business_entity_id IS NOT NULL
)
SELECT
    business_entity_id,
    birth_date,
    marital_status,
    marital_status_desc,
    yearly_income,
    gender,
    gender_desc,
    total_children,
    number_children_at_home,
    education,
    occupation,
    home_owner_flag,
    number_cars_owned,
    
    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;