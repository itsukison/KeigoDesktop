-- KeigoButton Desktop launch-health queries
-- PostHog project 549465; project timezone Asia/Tokyo.
-- Analysis window: 2026-08-21 through the current partial day, 2026-08-25.

-- 1. Launch-cohort activation, later-day return, and handled failures.
WITH user_launch AS (
  SELECT
    person_id,
    minIf(timestamp, event = 'Application Installed') AS installed_at,
    uniqExactIf(toDate(timestamp), event = 'Application Opened' AND properties.surface = 'macos') AS open_days,
    countIf(event = 'desktop_onboarding_completed' AND properties.surface = 'macos') AS onboarding_completions,
    countIf(event = 'desktop_accessibility_granted' AND properties.surface = 'macos') AS accessibility_grants,
    countIf(event = 'desktop_rewrite_completed' AND properties.surface = 'macos' AND properties.host_app_bundle_id != 'com.core7.keigobutton.mac') AS real_rewrites,
    countIf(event = 'desktop_rewrite_inserted' AND properties.surface = 'macos' AND properties.host_app_bundle_id != 'com.core7.keigobutton.mac') AS real_inserts,
    countIf(event = 'desktop_rewrite_copied' AND properties.surface = 'macos') AS copies,
    countIf(event = 'desktop_rewrite_failed' AND properties.surface = 'macos') AS failures
  FROM events
  WHERE timestamp >= toDateTime('2026-08-21 00:00:00')
    AND timestamp < now() + INTERVAL 1 DAY
    AND event IN (
      'Application Installed','Application Opened',
      'desktop_onboarding_completed','desktop_accessibility_granted',
      'desktop_rewrite_completed','desktop_rewrite_inserted',
      'desktop_rewrite_copied','desktop_rewrite_failed'
    )
  GROUP BY person_id
)
SELECT
  count() AS launched_users,
  countIf(accessibility_grants > 0) AS accessibility_users,
  countIf(onboarding_completions > 0) AS onboarded_users,
  countIf(real_rewrites > 0) AS real_rewrite_users,
  countIf(real_inserts > 0) AS real_insert_users,
  countIf(copies > 0) AS copy_users,
  countIf(failures > 0) AS users_with_failures,
  countIf(open_days >= 2) AS returned_later_day,
  round(avg(open_days), 2) AS avg_open_days,
  sum(real_rewrites) AS real_rewrites,
  sum(real_inserts) AS real_inserts,
  sum(failures) AS failures
FROM user_launch
WHERE installed_at >= toDateTime('2026-08-21 00:00:00');

-- 2. Exact calendar-day D1 return for eligible cohorts.
WITH user_launch AS (
  SELECT
    person_id,
    toDate(minIf(timestamp, event = 'Application Installed')) AS install_date,
    groupUniqArrayIf(toDate(timestamp), event = 'Application Opened' AND properties.surface = 'macos') AS open_dates,
    countIf(event = 'desktop_rewrite_completed' AND properties.surface = 'macos' AND properties.host_app_bundle_id != 'com.core7.keigobutton.mac') > 0 AS used_real_rewrite
  FROM events
  WHERE timestamp >= toDateTime('2026-08-21 00:00:00')
    AND timestamp < now() + INTERVAL 1 DAY
    AND event IN ('Application Installed','Application Opened','desktop_rewrite_completed')
  GROUP BY person_id
)
SELECT
  install_date,
  count() AS users,
  countIf(has(open_dates, addDays(install_date, 1))) AS d1_returners,
  round(100.0 * d1_returners / users, 1) AS d1_pct,
  countIf(used_real_rewrite) AS real_users
FROM user_launch
WHERE install_date BETWEEN toDate('2026-08-21') AND yesterday()
GROUP BY install_date
ORDER BY install_date;

-- 3. Actionable failure categories for launch users.
SELECT
  if(
    positionCaseInsensitive(properties.message, 'accessibility') > 0
      OR position(properties.message, 'アクセシビリティ') > 0,
    'Accessibility permission',
    'No readable text target'
  ) AS category,
  count() AS failures,
  uniqExact(person_id) AS users
FROM events
WHERE timestamp >= toDateTime('2026-08-21 00:00:00')
  AND event = 'desktop_rewrite_failed'
  AND properties.surface = 'macos'
  AND person_id IN (
    SELECT person_id
    FROM events
    WHERE timestamp >= toDateTime('2026-08-21 00:00:00')
      AND event = 'Application Installed'
  )
GROUP BY category
ORDER BY failures DESC;

-- 4. Exact current-telemetry outcomes, split between everyday and practice.
WITH attempts AS (
  SELECT
    properties.attempt_id AS attempt_id,
    countIf(event = 'desktop_rewrite_started') AS started,
    countIf(event = 'desktop_rewrite_completed') AS completed,
    countIf(event = 'desktop_rewrite_failed') AS failed,
    countIf(event = 'desktop_rewrite_inserted') AS inserted,
    countIf(event = 'desktop_rewrite_copied') AS copied,
    countIf(properties.is_tutorial = true) > 0 AS tutorial
  FROM events
  WHERE timestamp >= toDateTime('2026-08-24 00:00:00')
    AND event IN ('desktop_rewrite_started','desktop_rewrite_completed','desktop_rewrite_failed','desktop_rewrite_inserted','desktop_rewrite_copied')
    AND properties.surface = 'macos'
    AND isNotNull(properties.attempt_id)
    AND properties.attempt_id != ''
    AND person_id IN (
      SELECT person_id
      FROM events
      WHERE timestamp >= toDateTime('2026-08-21 00:00:00')
        AND event = 'Application Installed'
    )
  GROUP BY attempt_id
)
SELECT
  if(tutorial, 'practice', 'everyday') AS context,
  countIf(started > 0) AS started_attempts,
  countIf(completed > 0) AS completed_attempts,
  countIf(failed > 0) AS failed_attempts,
  countIf(inserted > 0 OR copied > 0) AS accepted_attempts,
  round(100.0 * failed_attempts / nullif(started_attempts, 0), 1) AS failure_pct,
  round(100.0 * accepted_attempts / nullif(completed_attempts, 0), 1) AS acceptance_pct
FROM attempts
GROUP BY context
ORDER BY context;

-- 5. Real-use latency for launch users, excluding onboarding practice.
SELECT
  toDate(timestamp) AS date,
  count() AS completed_rewrites,
  uniqExact(person_id) AS users,
  round(median(toFloat(properties.latency_ms)), 0) AS median_ms,
  round(quantile(0.95)(toFloat(properties.latency_ms)), 0) AS p95_ms
FROM events
WHERE timestamp >= toDateTime('2026-08-21 00:00:00')
  AND event = 'desktop_rewrite_completed'
  AND properties.surface = 'macos'
  AND properties.host_app_bundle_id != 'com.core7.keigobutton.mac'
  AND person_id IN (
    SELECT person_id
    FROM events
    WHERE timestamp >= toDateTime('2026-08-21 00:00:00')
      AND event = 'Application Installed'
  )
GROUP BY date
ORDER BY date;
