-- =============================================================================
-- L10 LAB - Create warehouses, set a resource monitor, read consumption
-- Section 2: Architecture & Fundamentals
-- Run top to bottom in a Snowsight worksheet. Role ACCOUNTADMIN.
-- STATUS: staged, NOT yet live-tested (pending Snowflake connection).
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- 1. Create a small, cost-safe warehouse. It starts suspended, parks itself
--    after 60 seconds idle, and wakes automatically on the next query.
CREATE WAREHOUSE IF NOT EXISTS COURSE_WH
  WAREHOUSE_SIZE   = 'XSMALL'
  AUTO_SUSPEND     = 60
  AUTO_RESUME      = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Course warehouse for the Snowflake on AWS labs';

USE WAREHOUSE COURSE_WH;

-- 2. Scaling UP: resize to make a single heavy query faster, then back down.
--    Resizing is instant and takes effect on the next query.
ALTER WAREHOUSE COURSE_WH SET WAREHOUSE_SIZE = 'SMALL';
SHOW WAREHOUSES LIKE 'COURSE_WH';
ALTER WAREHOUSE COURSE_WH SET WAREHOUSE_SIZE = 'XSMALL';

-- 2b. Warehouse TYPES. The default is STANDARD (what COURSE_WH is). A
--     SNOWPARK-OPTIMIZED warehouse has far more memory per node for heavy
--     Snowpark / Python / ML work, has a minimum size of MEDIUM, and costs more.
--     We create one (suspended, so it costs nothing) just to see the type column.
CREATE WAREHOUSE IF NOT EXISTS SNOWPARK_WH
  WAREHOUSE_SIZE = 'MEDIUM'
  WAREHOUSE_TYPE = 'SNOWPARK-OPTIMIZED'
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Demo of the Snowpark-optimized warehouse type';

-- Compare the two: look at the "type" column (STANDARD vs SNOWPARK-OPTIMIZED).
SHOW WAREHOUSES LIKE '%WH';

-- We do not need it for the rest of the course, so drop it to avoid any cost.
DROP WAREHOUSE IF EXISTS SNOWPARK_WH;

-- 3. Create a resource monitor: a hard guardrail on credit spend.
--    Notify at 75%, suspend after running queries finish at 90%,
--    and stop immediately at 100%.
CREATE OR REPLACE RESOURCE MONITOR COURSE_RM
  WITH
    CREDIT_QUOTA   = 5
    FREQUENCY      = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
  TRIGGERS
    ON 75  PERCENT DO NOTIFY
    ON 90  PERCENT DO SUSPEND
    ON 100 PERCENT DO SUSPEND_IMMEDIATE;

-- 4. Attach the monitor to our warehouse (warehouse-level cap). A monitor only
--    suspends warehouses, it does not stop serverless features.
ALTER WAREHOUSE COURSE_WH SET RESOURCE_MONITOR = COURSE_RM;
SHOW RESOURCE MONITORS;

-- 5. Generate a little work so there is something to measure.
USE WAREHOUSE COURSE_WH;
SELECT COUNT(*) AS sample_rows
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

-- 6. Read consumption the LOW-LATENCY way (current account, near real time):
--    the INFORMATION_SCHEMA table function. IMPORTANT: INFORMATION_SCHEMA is
--    per-database, so you must have a database in context first or it errors
--    with "Invalid identifier". We point at the sample database that always
--    exists. The metering data it returns is still account-wide.
USE DATABASE SNOWFLAKE_SAMPLE_DATA;
SELECT *
FROM TABLE(INFORMATION_SCHEMA.WAREHOUSE_METERING_HISTORY(
        DATE_RANGE_START => DATEADD('day', -1, CURRENT_DATE())))
ORDER BY START_TIME DESC;

-- 7. Read consumption the PRECISE way: ACCOUNT_USAGE (note: this view can lag
--    by up to a few hours, so on a brand-new account it may be nearly empty.
--    It is the account-wide historical source of truth over time).
SELECT WAREHOUSE_NAME, START_TIME, CREDITS_USED
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
ORDER BY START_TIME DESC
LIMIT 20;

-- 8. See what actually ran (query history for the current account/session).
SELECT QUERY_TEXT, WAREHOUSE_NAME, EXECUTION_STATUS, TOTAL_ELAPSED_TIME
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
ORDER BY START_TIME DESC
LIMIT 10;

-- Cleanup (run after recording):
-- ALTER WAREHOUSE COURSE_WH UNSET RESOURCE_MONITOR;
-- DROP RESOURCE MONITOR IF EXISTS COURSE_RM;
-- DROP WAREHOUSE IF EXISTS COURSE_WH;
