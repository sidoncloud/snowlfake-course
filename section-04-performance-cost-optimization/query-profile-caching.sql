-- =============================================================================
-- LAB - Query Profile, result cache and warehouse cache
-- Section 4: Performance & Cost Optimization
-- Run in a Snowsight worksheet as ACCOUNTADMIN. View the Query Profile in the
-- UI: open a query from Monitoring, then the Query Profile tab.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;

-- 1. Turn the result cache off so this query really executes, then run it and
--    open its Query Profile. Read the operator tree (TableScan, Aggregate,
--    Result) and the Statistics: Bytes scanned, Partitions scanned vs total
--    (equal here, no WHERE filter to prune), and Percentage scanned from cache.
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- 2. Turn the result cache back on and run the SAME query. It reuses the answer
--    immediately: the profile is a single QUERY RESULT REUSE node, zero bytes,
--    no warehouse.
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;
