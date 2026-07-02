-- =============================================================================
-- LAB - Query Profile, warehouse cache and result cache
-- Section 4: Performance & Cost Optimization
-- Run in a Snowsight worksheet as ACCOUNTADMIN. View each Query Profile in the
-- UI: open the query from Monitoring, then the Query Profile tab.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;

-- USE_CACHED_RESULT is the switch for the result cache. We turn it OFF so the
-- query really executes and we can read a real profile. Suspending a warehouse
-- throws away its local disk cache, so we suspend and resume to start cold.
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
ALTER WAREHOUSE COURSE_WH SUSPEND;
ALTER WAREHOUSE COURSE_WH RESUME;

-- RUN 1 (cold). Open the Query Profile. Operator tree: TableScan -> Aggregate ->
-- Result. In Statistics, Partitions scanned equals Partitions total (no WHERE to
-- prune), and Percentage scanned from cache reads 0 - everything came from storage.
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- RUN 2 (warm) - THE WAREHOUSE CACHE. Same query, still executing for real.
-- Percentage scanned from cache now reads 100: run 1 left the data on the
-- warehouse local disk, so run 2 read it from there instead of storage.
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- RUN 3 - THE RESULT CACHE. Turn the result cache back on and run the same query.
-- The profile collapses to a single QUERY RESULT REUSE node: zero bytes, no
-- warehouse. The query does not run at all - Snowflake hands back the saved answer.
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;
