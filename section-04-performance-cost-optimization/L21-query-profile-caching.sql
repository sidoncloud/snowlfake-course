-- =============================================================================
-- L21 LAB - Query Profile, result cache vs warehouse cache
-- Section 4: Performance & Cost Optimization
-- Run top to bottom in a Snowsight worksheet. Role ACCOUNTADMIN.
-- The Query Profile itself is viewed in the Snowsight UI (open a query from the
-- history, then the Query Profile tab). The SQL below gives you queries to look at.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;

-- 1. Run a query, then open its Query Profile (click the query in the history,
--    then the Query Profile tab). Note "Partitions scanned" versus the total,
--    and the operator tree showing where time went.
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- 2. RESULT CACHE. Run the exact same query again. It returns almost instantly,
--    because Snowflake reuses the stored result. The profile shows a single
--    QUERY RESULT REUSE node, and it scans zero bytes and uses no warehouse.
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- 3. Turn the result cache off so you can feel the difference, then run it again.
--    Now it actually executes on the warehouse. Turn the cache back on after.
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
SELECT o_orderpriority, COUNT(*) AS orders, SUM(o_totalprice) AS revenue
FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS
GROUP BY o_orderpriority;

-- 4. WAREHOUSE (local disk) CACHE. With the result cache still off, run a query
--    and then a different follow-up over the same table. The warehouse kept the
--    data it just read on local disk, so the second query reads more from cache
--    and less from storage. Check "Percentage scanned from cache" in each profile.
SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS WHERE o_totalprice > 100000;
SELECT COUNT(*) FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS WHERE o_totalprice > 200000;

-- Put the result cache back on for normal work.
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
