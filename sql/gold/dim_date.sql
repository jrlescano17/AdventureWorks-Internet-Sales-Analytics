WITH cte_sequence AS (

    SELECT *
    FROM generate_series(
        DATE '2011-01-01',
        DATE '2014-12-31',
        INTERVAL 1 DAY
    ) AS t(d)

)
SELECT
    CAST(strftime(d, '%Y%m%d') AS INTEGER)      AS date_key,
    CAST(d AS DATE)                             AS date,
    dayofweek(d) + 1                            AS day_number_of_week,
    UPPER(SUBSTR(strftime(d, '%A'), 1, 1))
        || LOWER(SUBSTR(strftime(d, '%A'), 2))  AS day_name_of_week,
    day(d)                                      AS day_number_of_month,
    dayofyear(d)                                AS day_number_of_year,
    week(d)                                     AS week_number_of_year,
    UPPER(SUBSTR(strftime(d, '%B'), 1, 1))
        || LOWER(SUBSTR(strftime(d, '%B'), 2))  AS month_name,
    UPPER(SUBSTR(strftime(d, '%b'), 1, 1))
        || LOWER(SUBSTR(strftime(d, '%b'), 2))  AS short_month_name,
    month(d)                                    AS month_number_of_year,
    quarter(d)                                  AS calendar_quarter,
    year(d)                                     AS calendar_year,
    CASE
        WHEN month(d) <= 6 THEN 1
        ELSE 2
    END                                         AS calendar_semester,
    quarter(d)                                  AS fiscal_quarter,
    year(d)                                     AS fiscal_year,
    CASE
        WHEN month(d) <= 6 THEN 1
        ELSE 2
    END                                         AS fiscal_semester
FROM cte_sequence