-- =============================================================================
-- LAB - Query Profile, result cache and warehouse cache
-- Section 4: Performance & Cost Optimization
-- Run in a Snowsight worksheet as ACCOUNTADMIN. The Query Profile is viewed in
-- the UI: open a query from Monitoring, then the Query Profile tab.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;

-- 1. Run this, then open its Query Profile. Read the operator tree (TableScan,
--    Aggregate, Result), and the Statistics panel: Bytes scanned, Partitions
--    scanned vs total (equal here, no WHERE filter to prune), and Percentage
--    scanned from cache (0 on this first cold run).
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- 2. RESULT CACHE. Run the EXACT same query again, a few times. It may reuse on
--    the second run or need a third. When it does, the profile collapses to a
--    single QUERY RESULT REUSE node and scans zero bytes.
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- 3. Turn the result cache off so every run really executes.
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- 4. WAREHOUSE CACHE. Run the query again a few times, with the result cache off.
--    It executes each time, but watch Percentage scanned from cache climb from 0
--    toward 100 percent, as the warehouse keeps the table's data on local disk.
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- 5. Put the result cache back on for normal work.
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
