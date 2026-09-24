WITH cleaned AS (
    SELECT
        CAST("BusinessEntityID" AS INT)         AS business_entity_id,
        NULLIF(UPPER(TRIM("PersonType")), '')   AS person_type,
        CAST("NameStyle" AS BOOLEAN)            AS name_style,
        NULLIF(TRIM("Title"), '')               AS title,
        NULLIF(TRIM("FirstName"), '')           AS first_name,
        NULLIF(TRIM("MiddleName"), '')          AS middle_name,
        NULLIF(TRIM("LastName"), '')            AS last_name,
        NULLIF(TRIM("Suffix"), '')              AS suffix,
        CAST("EmailPromotion" AS INT)           AS email_promotion,
        CAST("ModifiedDate" AS TIMESTAMP)       AS modified_date,
        _ingestion_ts
    FROM read_parquet('data/bronze/PersonPerson.parquet')
),
normalized AS (
    SELECT
        *,
        CASE
            WHEN person_type IS NULL THEN NULL
            WHEN person_type = 'SC' THEN 'Store Contact'
            WHEN person_type = 'IN' THEN 'Individual Customer'
            WHEN person_type = 'SP' THEN 'Sales Person'
            WHEN person_type = 'EM' THEN 'Employee'
            WHEN person_type = 'VC' THEN 'Vendor Contact'
            WHEN person_type = 'GC' THEN 'General Contact'
            ELSE 'Unknown'
        END AS person_type_desc
    FROM cleaned
),
deduplicated AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY business_entity_id
            ORDER BY modified_date DESC, _ingestion_ts DESC
        ) AS rn
    FROM normalized
    WHERE business_entity_id IS NOT NULL
)
SELECT
    business_entity_id,
    person_type,
    person_type_desc,
    name_style,
    title,
    first_name,
    middle_name,
    last_name,
    suffix,
    email_promotion,
    modified_date,

    --metadata
    _ingestion_ts,
    CURRENT_TIMESTAMP AS _transform_ts
FROM deduplicated
WHERE rn = 1;