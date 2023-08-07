-- make sure that you have a dashboards dataset in region as the source data

CREATE OR REPLACE TABLE `dashboards.UserRetention` AS (
  WITH calculated_number_of_users AS (
      SELECT 
            cohort_year,
            cohort_month, 
            first_date_of_active_month, 
            COUNT(DISTINCT user_pseudo_id) AS number_of_users,
            analytics_consent,
            geo_location
      FROM `dashboards.UserRetention_UsersActivities`
      GROUP BY 1, 2, 3, 5, 6
  ),
  calculated_month_diff AS (
      SELECT cohort_year, 
          cohort_month,
          DATE_DIFF(first_date_of_active_month, DATE(cohort_year, cohort_month, 1), MONTH) AS month_diff,
          number_of_users,
          analytics_consent,
          geo_location
      FROM calculated_number_of_users AS d
  ),
  max_number_of_users_for_cohort AS (
      SELECT *
      FROM calculated_month_diff
      WHERE month_diff = 0
  )
  SELECT 
      d.cohort_year AS cohort_year, 
      d.cohort_month AS cohort_month,
      d.month_diff AS month_diff,
      d.number_of_users AS number_of_users,
      m.number_of_users AS max_number_of_users,
      d.analytics_consent AS analytics_consent,
      d.geo_location AS geo_location
  FROM calculated_month_diff AS d
  LEFT JOIN max_number_of_users_for_cohort m
      ON d.cohort_year = m.cohort_year 
          AND d.cohort_month = m.cohort_month 
          AND d.analytics_consent = m.analytics_consent
          AND d.geo_location = m.geo_location
);

MERGE `dashboards.UserRetention` AS existing_data
USING (
  WITH month_zero_data AS (
    SELECT *
    FROM `dashboards.UserRetention`
    WHERE month_diff = 0
  ),
  generated_month_diff_options AS (
    SELECT generated_month_diff
    FROM UNNEST(
      GENERATE_ARRAY
      (
        0,
        (SELECT DATE_DIFF(
          CURRENT_DATE(), 
          (
            SELECT MIN(cohort_date) 
            FROM (
              SELECT DATE(cohort_year, cohort_month, 1) AS cohort_date
              FROM `best-seller-books-379513.dashboards.UserRetention`
            )
          ), 
          MONTH)
        )
      )
    ) AS generated_month_diff
  )
  SELECT cohort_year,
    cohort_month,
    generated_month_diff AS month_diff,
    0 AS number_of_users,
    max_number_of_users,
    analytics_consent,
    geo_location
  FROM month_zero_data, generated_month_diff_options
  WHERE generated_month_diff != 0 AND generated_month_diff <= DATE_DIFF(CURRENT_DATE(), DATE(cohort_year, cohort_month, 1), MONTH)
) AS new_data
ON existing_data.cohort_year = new_data.cohort_year
    AND existing_data.cohort_month = new_data.cohort_month
    AND existing_data.month_diff = new_data.month_diff
    AND existing_data.max_number_of_users = new_data.max_number_of_users
    AND existing_data.analytics_consent = new_data.analytics_consent
    AND existing_data.geo_location = new_data.geo_location
WHEN NOT MATCHED THEN
INSERT VALUES(cohort_year, cohort_month, month_diff, number_of_users, max_number_of_users, analytics_consent, geo_location);

