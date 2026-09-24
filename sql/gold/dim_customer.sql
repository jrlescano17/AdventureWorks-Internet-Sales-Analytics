WITH cte_person AS (
    SELECT
        business_entity_id,
        CONCAT_WS(' ', first_name, middle_name, last_name) AS customer_name,
        title,
        first_name,
        middle_name,
        last_name,
        name_style,
        suffix
    FROM read_parquet('data/silver/person_person.parquet')
    WHERE person_type = 'IN'
),
cte_phone AS (
    SELECT business_entity_id, phone_number
    FROM (
        SELECT
            ROW_NUMBER() OVER (PARTITION BY business_entity_id ORDER BY modified_date DESC) AS fila,
            business_entity_id,
            phone_number
        FROM read_parquet('data/silver/person_phone.parquet')
    ) t
    WHERE fila = 1
),
cte_address AS (
    SELECT
        business_entity_id,
        address_id,
        address_line1,
        address_line2,
        city,
        postal_code,
        state_province_id
    FROM (
        SELECT
            ROW_NUMBER() OVER (PARTITION BY ba.business_entity_id ORDER BY a.address_id DESC) AS fila,
            ba.business_entity_id,
            a.address_id,
            a.address_line1,
            a.address_line2,
            a.city,
            a.postal_code,
            a.state_province_id
        FROM read_parquet('data/silver/person_business_entity_address.parquet') ba
        LEFT JOIN read_parquet('data/silver/person_address.parquet') a ON ba.address_id = a.address_id
        WHERE ba.address_type_id = 2
    ) t
    WHERE fila = 1
),
cte_email AS (
    SELECT business_entity_id, email_address
    FROM (
        SELECT
            ROW_NUMBER() OVER (PARTITION BY business_entity_id ORDER BY email_address_id DESC) AS fila,
            business_entity_id,
            email_address
        FROM read_parquet('data/silver/person_email_address.parquet')
    ) t
    WHERE fila = 1
),
cte_first_purchase AS (
    SELECT
        customer_id,
        MIN(order_date) AS date_first_purchase
    FROM read_parquet('data/silver/sales_order_header.parquet')
    GROUP BY customer_id
)
SELECT
    -1 AS customer_key,
    -1 AS geography_key,
    '-1' AS customer_alternate_key,
    'Unknown' AS customer_name,

    NULL AS title,
    NULL AS first_name,
    NULL AS middle_name,
    NULL AS last_name,
    NULL AS name_style,
    NULL AS birth_date,
    NULL AS marital_status,
    'Unknown' AS marital_status_desc,
    NULL AS suffix,
    NULL AS gender,
    'Unknown' AS gender_desc,
    NULL AS email_address,
    NULL AS yearly_income,
    NULL AS total_children,
    NULL AS number_children_at_home,
    'Unknown' AS education,
    'Unknown' AS occupation,
    NULL AS home_owner_flag,
    NULL AS number_cars_owned,
    NULL AS address_line1,
    NULL AS address_line2,
    NULL AS phone_number,
    NULL AS date_first_purchase,

    NULL AS _hash,
    CURRENT_TIMESTAMP AS _insert_ts,
    CURRENT_TIMESTAMP AS _update_ts

UNION ALL

SELECT
    ROW_NUMBER() OVER (
        ORDER BY account_number
    ) AS customer_key,
    COALESCE(g.geography_key, -1)   AS geography_key,
    c.account_number AS customer_alternate_key,
    p.customer_name,
    p.title,
    p.first_name,
    p.middle_name,
    p.last_name,
    p.name_style,
    pd.birth_date,
    pd.marital_status,
    pd.marital_status_desc,
    p.suffix,
    pd.gender,
    pd.gender_desc,
    ce.email_address,
    pd.yearly_income,
    pd.total_children,
    pd.number_children_at_home,
    pd.education,
    pd.occupation,
    pd.home_owner_flag,
    pd.number_cars_owned,
    a.address_line1,
    a.address_line2,
    cp.phone_number,
    fp.date_first_purchase,

    unhex(sha256(
        concat_ws('||',
            CAST(COALESCE(g.geography_key, -1) AS VARCHAR),
            COALESCE(p.customer_name, ''),
            COALESCE(p.title, ''),
            COALESCE(p.first_name, ''),
            COALESCE(p.middle_name, ''),
            COALESCE(p.last_name, ''),
            COALESCE(CAST(p.name_style AS VARCHAR), ''),
            COALESCE(CAST(pd.birth_date  AS VARCHAR), ''),
            COALESCE(pd.marital_status, ''),
            COALESCE(pd.marital_status_desc, ''),
            COALESCE(p.suffix, ''),
            COALESCE(pd.gender, ''),
            COALESCE(pd.gender_desc, ''),
            COALESCE(ce.email_address, ''),
            COALESCE(pd.yearly_income, ''),
            COALESCE(CAST(pd.total_children AS VARCHAR), '' ),
            COALESCE(CAST(pd.number_children_at_home AS VARCHAR), ''),
            COALESCE(pd.education, ''),
            COALESCE(pd.occupation, ''),
            COALESCE(CAST(pd.home_owner_flag AS VARCHAR), ''),
            COALESCE(CAST(pd.number_cars_owned AS VARCHAR), ''),
            COALESCE(a.address_line1, ''),
            COALESCE(a.address_line2, ''),
            COALESCE(cp.phone_number, ''),
            COALESCE(CAST(fp.date_first_purchase AS VARCHAR), '')
        )
    )) AS _hash,

    CURRENT_TIMESTAMP AS _insert_ts,
    CURRENT_TIMESTAMP AS _update_ts

FROM cte_person p
LEFT JOIN read_parquet('data/silver/sales_customer.parquet') c              ON p.business_entity_id = c.person_id
LEFT JOIN cte_address a                        ON p.business_entity_id = a.business_entity_id
LEFT JOIN read_parquet('data/silver/person_demographics.parquet') pd        ON p.business_entity_id = pd.business_entity_id
LEFT JOIN cte_phone cp                         ON p.business_entity_id = cp.business_entity_id
LEFT JOIN cte_email ce                         ON p.business_entity_id = ce.business_entity_id
LEFT JOIN cte_first_purchase fp                ON c.customer_id = fp.customer_id
LEFT JOIN read_parquet('data/silver/person_state_province.parquet') sp      ON a.state_province_id = sp.state_province_id
LEFT JOIN read_parquet('data/gold/dim_geography.parquet') g
    ON  a.city                  = g.city
    AND a.postal_code           = g.postal_code
    AND sp.state_province_code  = g.state_province_code
    AND sp.country_region_code  = g.country_region_code