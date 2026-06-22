-- =============================================================================
-- L18 LAB - Recover data with Time Travel; clone a database instantly
-- Section 3: Tables, Views & Semi-Structured Data
-- PREREQ: run L12 first (uses SNOWFLAKE_LABS.RETAIL.orders as the source).
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
USE SCHEMA SNOWFLAKE_LABS.RETAIL;

-- 1. A working copy to experiment on safely.
CREATE OR REPLACE TABLE tt_demo AS SELECT * FROM orders;
SELECT COUNT(*) AS rows_before FROM tt_demo;

-- 2. The mistake: delete all cancelled orders. Capture the delete's query id
--    right away, because Time Travel by statement needs THIS id, and
--    LAST_QUERY_ID() would drift to later statements as we keep working.
DELETE FROM tt_demo WHERE status = 'CANCELLED';
SET del_qid = LAST_QUERY_ID();
SELECT COUNT(*) AS rows_after_delete FROM tt_demo;

-- 3. TIME TRAVEL by statement: query the table as it was BEFORE that delete.
SELECT COUNT(*) AS rows_before_delete
FROM tt_demo BEFORE (STATEMENT => $del_qid);

-- 4. TIME TRAVEL by offset: the table as it was 60 seconds ago.
SELECT COUNT(*) AS rows_60s_ago
FROM tt_demo AT (OFFSET => -60);

-- 5. Restore the deleted rows by reading them from before the delete and
--    inserting back the ones now missing.
INSERT INTO tt_demo
SELECT * FROM tt_demo BEFORE (STATEMENT => $del_qid)
WHERE status = 'CANCELLED'
  AND order_id NOT IN (SELECT order_id FROM tt_demo);
SELECT COUNT(*) AS rows_restored FROM tt_demo;

-- 6. UNDROP: drop the whole table, then bring it straight back.
DROP TABLE tt_demo;
UNDROP TABLE tt_demo;
SELECT COUNT(*) AS rows_after_undrop FROM tt_demo;

-- 7. ZERO-COPY CLONE: an instant, independent copy that costs no extra storage
--    at first, because it points at the same micro-partitions.
CREATE TABLE tt_demo_clone CLONE tt_demo;
SELECT COUNT(*) AS clone_rows FROM tt_demo_clone;

-- 8. Prove independence: change the clone, original is untouched.
DELETE FROM tt_demo_clone WHERE status = 'PENDING';
SELECT
    (SELECT COUNT(*) FROM tt_demo)        AS original_rows,
    (SELECT COUNT(*) FROM tt_demo_clone)  AS clone_rows;

-- 9. Clone an entire schema in one command (the dev/test environment trick).
CREATE SCHEMA SNOWFLAKE_LABS.RETAIL_CLONE CLONE SNOWFLAKE_LABS.RETAIL;
SHOW TABLES IN SCHEMA SNOWFLAKE_LABS.RETAIL_CLONE;

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP TABLE  IF EXISTS tt_demo;
-- DROP TABLE  IF EXISTS tt_demo_clone;
-- DROP SCHEMA IF EXISTS SNOWFLAKE_LABS.RETAIL_CLONE;
