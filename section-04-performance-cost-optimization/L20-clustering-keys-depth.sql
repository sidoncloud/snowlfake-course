-- =============================================================================
-- L20 LAB - Clustering keys, clustering depth and overlap
-- Section 4: Performance & Cost Optimization
-- Run top to bottom in a Snowsight worksheet. Role ACCOUNTADMIN.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_LABS;
CREATE SCHEMA   IF NOT EXISTS SNOWFLAKE_LABS.PERF;
USE SCHEMA SNOWFLAKE_LABS.PERF;

-- 1. Copy a real table. It loads in its natural order, by order key, not by date.
CREATE OR REPLACE TABLE orders AS
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS;

-- 2. Check how well it clusters on o_orderdate. Read average_depth in the result:
--    lower is better, 1 is perfect. It will be high here, because the rows are
--    not stored in date order.
SELECT SYSTEM$CLUSTERING_INFORMATION('orders', '(o_orderdate)');

-- 3. Make a copy that is physically sorted by o_orderdate, and check again.
--    average_depth drops close to 1, near-perfect clustering on the date.
CREATE OR REPLACE TABLE orders_sorted AS
SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS ORDER BY o_orderdate;
SELECT SYSTEM$CLUSTERING_INFORMATION('orders_sorted', '(o_orderdate)');

-- 4. Define a clustering key on the original table, so Snowflake keeps it
--    clustered automatically in the background as new data arrives.
ALTER TABLE orders CLUSTER BY (o_orderdate);
SHOW TABLES LIKE 'orders';   -- see the cluster_by value

-- 5. See the payoff: a date-filtered query reads far fewer micro-partitions on
--    the well-clustered table. Run both, then open the Query Profile on each and
--    compare "Partitions scanned" against "Partitions total".
SELECT COUNT(*) FROM orders_sorted WHERE o_orderdate BETWEEN '1995-01-01' AND '1995-01-31';
SELECT COUNT(*) FROM orders        WHERE o_orderdate BETWEEN '1995-01-01' AND '1995-01-31';

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP TABLE IF EXISTS orders;
-- DROP TABLE IF EXISTS orders_sorted;
