MERGE `dashboards.UserRetention_UsersActivities` AS existing_data
USING (
  WITH events AS (
    SELECT
          user_pseudo_id,
          PARSE_DATE('%Y%m%d', event_date) AS event_date,
          event_timestamp,
          e.geo.country AS geo_location,
          (SELECT value.string_value FROM UNNEST(e.user_properties) WHERE key = "analytic_type") AS analytics_consent
    FROM `analytics.events_*` AS e -- source
    WHERE event_name = 'user_engagement'
          AND _TABLE_SUFFIX BETWEEN '20230101' AND '20230630' -- here define date range
    GROUP BY 1, 2, 3, 4, 5
  ),
  generated_dates AS (
    SELECT generated_date
    FROM UNNEST(GENERATE_DATE_ARRAY(
      IF(
        (SELECT MAX(first_date_of_active_month) FROM `dashboards.UserRetention_UsersActivities`) IS NULL,
        '2023-01-01',
        (SELECT MAX(first_date_of_active_month) FROM `dashboards.UserRetention_UsersActivities`)
      ),
      CURRENT_DATE(),
      INTERVAL 1 MONTH)
    ) AS generated_date
  ),
  user_activities AS (
    SELECT
          user_pseudo_id,
          generated_date AS first_date_of_active_month,
          MAX(event_date) AS date_of_last_activity,
    FROM events, generated_dates
    WHERE EXTRACT(YEAR FROM event_date) = EXTRACT(YEAR FROM generated_date)
          AND EXTRACT(MONTH FROM event_date) = EXTRACT(MONTH FROM generated_date)
    GROUP BY 1, 2
  ),
  user_activities_joined_with_existing_data AS (
    SELECT new_users.user_pseudo_id,
            new_users.first_date_of_active_month,
            new_users.date_of_last_activity,
            (
              existing_user.user_pseudo_id IS NOT NULL
            ) AS does_user_exist,
            existing_user.cohort_year         AS existing_user_cohort_year,
            existing_user.cohort_month        AS existing_user_cohort_month,
            existing_user.analytics_consent   AS existing_user_analytics_consent,
            existing_user.geo_location        AS existing_user_geo_location
    FROM user_activities AS new_users
    LEFT JOIN `dashboards.UserRetention_UsersActivities` AS existing_user
      ON new_users.user_pseudo_id = existing_user.user_pseudo_id
    GROUP BY 1, 2, 3, 4, 5 , 6, 7, 8
  ),
  existing_users AS (
    SELECT 
            LAST_VALUE(existing_user_cohort_year) OVER (
              PARTITION BY user_pseudo_id
              ORDER BY first_date_of_active_month
              ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ) AS cohort_year,
            LAST_VALUE(existing_user_cohort_month) OVER (
              PARTITION BY user_pseudo_id
              ORDER BY first_date_of_active_month
              ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ) AS cohort_month,
            
            first_date_of_active_month,
            user_pseudo_id,
            date_of_last_activity,

            LAST_VALUE(existing_user_analytics_consent) OVER (
              PARTITION BY user_pseudo_id
              ORDER BY first_date_of_active_month
              ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ) AS analytics_consent,
            LAST_VALUE(existing_user_geo_location) OVER (
              PARTITION BY user_pseudo_id
              ORDER BY first_date_of_active_month
              ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
            ) AS geo_location,
    FROM user_activities_joined_with_existing_data
    WHERE does_user_exist = true
  ),
  new_users_cohort AS (
    SELECT
          new_user.user_pseudo_id,
          MIN(events.event_date) AS cohort_date,
          MIN(events.geo_location) AS geo_location,
          MIN(events.analytics_consent) AS analytics_consent
    FROM user_activities_joined_with_existing_data AS new_user
    LEFT JOIN events
      ON new_user.user_pseudo_id = events.user_pseudo_id
    WHERE new_user.does_user_exist = false
    GROUP BY 1
  ),
  new_users_cohort_with_activities AS (
    SELECT cohort.user_pseudo_id, 
            EXTRACT(YEAR FROM cohort.cohort_date) AS cohort_year,
            EXTRACT(MONTH FROM cohort.cohort_date) AS cohort_month, 
            new_user_activities.first_date_of_active_month, 
            new_user_activities.date_of_last_activity,
            cohort.geo_location,
            cohort.analytics_consent
    FROM new_users_cohort AS cohort
    LEFT JOIN user_activities_joined_with_existing_data AS new_user_activities
      ON cohort.user_pseudo_id = new_user_activities.user_pseudo_id
    WHERE new_user_activities.does_user_exist = false
  )

  SELECT cohort_year,
          cohort_month,
          user_pseudo_id,
          first_date_of_active_month,
          date_of_last_activity,
          analytics_consent,
          geo_location
  FROM new_users_cohort_with_activities
  UNION ALL
  SELECT cohort_year,
          cohort_month,
          user_pseudo_id,
          first_date_of_active_month,
          date_of_last_activity,
          analytics_consent,
          geo_location
  FROM existing_users 
) AS new_data
ON existing_data.user_pseudo_id = new_data.user_pseudo_id
    AND existing_data.first_date_of_active_month = new_data.first_date_of_active_month
WHEN MATCHED AND existing_data.date_of_last_activity != new_data.date_of_last_activity THEN
  UPDATE SET date_of_last_activity = new_data.date_of_last_activity
WHEN NOT MATCHED THEN
  INSERT VALUES(cohort_year, cohort_month, user_pseudo_id, first_date_of_active_month, date_of_last_activity, analytics_consent, geo_location)
