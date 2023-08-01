-- make sure that you have a dashboards dataset in region as the source data

CREATE OR REPLACE TABLE `dashboards.UserRetention_UsersActivities` AS (
  WITH events AS (
    SELECT
          user_pseudo_id,
          PARSE_DATE('%Y%m%d', event_date) AS event_date,
          event_timestamp,
          e.geo.country AS geo_location,
          (SELECT value.string_value FROM UNNEST(e.user_properties) WHERE key = "analytic_type") AS analytics_consent
    FROM `best-seller-books-379513.analytics.events_*` AS e -- source
    WHERE event_name = 'user_engagement'
    GROUP BY 1, 2, 3, 4, 5
  ),
  activity_dates AS (
    SELECT generated_date
    FROM UNNEST(GENERATE_DATE_ARRAY(
      '2023-01-01',
      CURRENT_DATE(),
      INTERVAL 1 MONTH)
    ) AS generated_date
  ),
  user_activities AS (
    SELECT
          user_pseudo_id,
          generated_date AS first_date_of_active_month,
          MAX(event_date) AS date_of_last_activity,
    FROM events, activity_dates
    WHERE EXTRACT(YEAR FROM event_date) = EXTRACT(YEAR FROM generated_date)
          AND EXTRACT(MONTH FROM event_date) = EXTRACT(MONTH FROM generated_date)
    GROUP BY 1, 2
  ),
  new_users_cohort AS (
    SELECT
          user_pseudo_id,
          MIN(event_date) AS cohort_date, -- date of first event
          MIN(geo_location) AS geo_location,
          MIN(analytics_consent) AS analytics_consent
    FROM events
    GROUP BY 1
  ),
  new_users_cohort_with_activities AS (
    SELECT cohort.user_pseudo_id, 
            cohort.cohort_date, 
            activities.first_date_of_active_month, 
            activities.date_of_last_activity,
            cohort.geo_location,
            cohort.analytics_consent
    FROM new_users_cohort AS cohort
    LEFT JOIN user_activities AS activities
      ON cohort.user_pseudo_id = activities.user_pseudo_id
  )
  SELECT EXTRACT(YEAR FROM cohort_date) AS cohort_year,
          EXTRACT(MONTH FROM cohort_date) AS cohort_month,
          user_pseudo_id,
          first_date_of_active_month,
          date_of_last_activity,
          analytics_consent,
          geo_location
  FROM new_users_cohort_with_activities
)