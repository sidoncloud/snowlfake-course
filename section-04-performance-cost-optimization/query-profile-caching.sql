-- =============================================================================
-- LAB - Query Profile, result cache and warehouse cache
-- Section 4: Performance & Cost Optimization
-- Run in a Snowsight worksheet as ACCOUNTADMIN. The Query Profile is viewed in
-- the UI: open a query from Monitoring, then the Query Profile tab.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;

-- Keep the warehouse awake through the lab so its local cache does not reset
-- mid-demo. We set it back to 60 at the end.
ALTER WAREHOUSE COURSE_WH SET AUTO_SUSPEND = 600;

-- 1. Result cache OFF, so this run truly executes. Run it, then open the Query
--    Profile. Read the operator tree (TableScan, Aggregate, Result) and the
--    Statistics: Bytes scanned, Partitions scanned vs total (equal here, no WHERE
--    filter to prune), and Percentage scanned from cache (the warehouse local disk
--    cache, higher the more this warehouse has recently read this data).
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- 2. Result cache ON, then run the SAME query. It reuses immediately, because the
--    run above already stored the answer: the profile is a single QUERY RESULT
--    REUSE node, zero bytes, no warehouse. (Any change to a table resets its
--    cached results, so we demo on this unchanged sample table.)
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- 3. Put auto-suspend back to a thrifty value.
ALTER WAREHOUSE COURSE_WH SET AUTO_SUSPEND = 60;
