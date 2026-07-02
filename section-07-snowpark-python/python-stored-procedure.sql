-- =============================================================================
-- LAB - Python Stored Procedure
-- Section 7: Snowpark, Data Engineering in Python
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
--
-- A procedure DOES work: it reads a table, transforms it with Snowpark, writes
-- the result, and returns a status. You call it on its own, not inside a query.
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COURSE_WH;
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_LABS;
CREATE SCHEMA   IF NOT EXISTS SNOWFLAKE_LABS.SNOWPARK;
USE SCHEMA SNOWFLAKE_LABS.SNOWPARK;

-- Two small tables so the lab is self-contained.
CREATE OR REPLACE TABLE customers (
    customer_id INT, name STRING, region STRING);
INSERT INTO customers VALUES
    (1,'Ava','WEST'),(2,'Liam','EAST'),(3,'Mia','WEST'),
    (4,'Noah','EAST'),(5,'Ivy','SOUTH');
CREATE OR REPLACE TABLE orders (
    order_id INT, customer_id INT, amount NUMBER(10,2), status STRING);
INSERT INTO orders VALUES
    (101,1,120.00,'COMPLETED'),(102,1,80.00,'COMPLETED'),
    (103,2,200.00,'COMPLETED'),(104,2,50.00,'CANCELLED'),
    (105,3,300.00,'COMPLETED'),(106,4,150.00,'COMPLETED'),
    (107,4,90.00,'COMPLETED'),(108,5,60.00,'CANCELLED'),
    (109,5,220.00,'COMPLETED'),(110,3,40.00,'COMPLETED');

-- 1. Create the procedure. LANGUAGE PYTHON, and the handler receives a Snowpark
--    session as its first argument, so the same DataFrame API from the earlier
--    lab runs here, only server-side. PACKAGES pulls in snowpark from Anaconda.
CREATE OR REPLACE PROCEDURE build_revenue_by_region(source_table STRING, target_table STRING)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
AS
$$
from snowflake.snowpark.functions import col, sum as sum_, count as count_

def run(session, source_table, target_table):
    orders = session.table(source_table)
    customers = session.table('customers')
    completed = orders.filter(col('status') == 'COMPLETED')
    result = (completed.join(customers,
                             completed['customer_id'] == customers['customer_id'])
              .group_by(customers['region'])
              .agg(sum_(completed['amount']).alias('revenue'),
                   count_(completed['order_id']).alias('order_count')))
    result.write.mode('overwrite').save_as_table(target_table)
    n = session.table(target_table).count()
    return f'Wrote {n} region rows to {target_table}'
$$;

-- 2. Call it on its own with CALL. It runs the whole read-transform-write job
--    inside Snowflake and returns the status string.
CALL build_revenue_by_region('orders', 'revenue_by_region');

-- 3. The procedure wrote a real table. Read what it produced.
SELECT region, revenue, order_count
FROM revenue_by_region ORDER BY revenue DESC;

-- Cleanup (optional, run this when you are done to remove what the lab created):
-- DROP PROCEDURE IF EXISTS build_revenue_by_region(STRING, STRING);
-- DROP TABLE IF EXISTS revenue_by_region;
-- DROP TABLE IF EXISTS orders;
-- DROP TABLE IF EXISTS customers;
