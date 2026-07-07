-- =============================================================================
-- LAB - Python Stored Procedure, deployed and scheduled
-- Section 7: Snowpark, Data Engineering in Python
-- Run in a Snowsight worksheet as ACCOUNTADMIN.
--
-- A procedure does a whole job: it reads a table, transforms it with Snowpark,
-- and writes the result. Here we deploy that procedure as a permanent object,
-- then schedule it with a task so it runs server-side on its own, the way a
-- Snowpark transformation goes from notebook code to a running production job.
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

-- 1. Deploy the procedure as a PERMANENT object. CREATE PROCEDURE persists in
--    the schema until you drop it. LANGUAGE PYTHON, and the handler receives a
--    Snowpark session as its first argument, so the same DataFrame API from the
--    earlier lab runs here, only server-side. PACKAGES pulls snowpark from Anaconda.
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

-- The procedure is now a real object in the schema. Confirm it is there.
SHOW PROCEDURES LIKE 'BUILD_REVENUE_BY_REGION' IN SCHEMA SNOWFLAKE_LABS.SNOWPARK;

-- 2. Call it once by hand with CALL to prove the job works. You call a procedure
--    on its own, not inside a SELECT, because it is doing work, not computing a column.
CALL build_revenue_by_region('orders', 'revenue_by_region');

-- 3. The procedure wrote a real table. Read what it produced.
SELECT region, revenue, order_count
FROM revenue_by_region ORDER BY revenue DESC;

-- 4. Schedule it. A task wraps the CALL and runs it server-side on a cadence.
--    WAREHOUSE names the compute, SCHEDULE sets the cadence, and the body is the
--    same CALL you just ran by hand. A new task is created suspended.
CREATE OR REPLACE TASK deploy_revenue_by_region
    WAREHOUSE = COURSE_WH
    SCHEDULE  = '1 MINUTE'
    AS
    CALL build_revenue_by_region('orders', 'revenue_by_region');

-- 5. RESUME turns the task on. Its state moves from suspended to started, and
--    from now on Snowflake fires the CALL every minute with no one at the keyboard.
ALTER TASK deploy_revenue_by_region RESUME;
SHOW TASKS LIKE 'DEPLOY_REVENUE_BY_REGION' IN SCHEMA SNOWFLAKE_LABS.SNOWPARK;

-- 6. Prove it runs on its own against fresh data. Add a new completed order for an
--    EAST customer, then let the next scheduled run pick it up. Wait about a minute,
--    or trigger a run immediately with EXECUTE TASK if you do not want to wait.
INSERT INTO orders VALUES (111,2,500.00,'COMPLETED');
-- EXECUTE TASK deploy_revenue_by_region;   -- optional, forces a run right now

-- 7. Watch the runs. TASK_HISTORY shows each fire and its state moving from
--    SCHEDULED to EXECUTING to SUCCEEDED. Re-run this until you see a SUCCEEDED row.
SELECT name, state, scheduled_time, completed_time
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    TASK_NAME => 'DEPLOY_REVENUE_BY_REGION'))
ORDER BY scheduled_time DESC
LIMIT 10;

-- 8. Read the output table again. The scheduled run rebuilt it, so EAST now
--    includes the 500 from order 111. The job updated the data with no manual call.
SELECT region, revenue, order_count
FROM revenue_by_region ORDER BY revenue DESC;

-- Cleanup (run this when you are done so the task stops consuming credits):
-- ALTER TASK deploy_revenue_by_region SUSPEND;
-- DROP TASK IF EXISTS deploy_revenue_by_region;
-- DROP PROCEDURE IF EXISTS build_revenue_by_region(STRING, STRING);
-- DROP TABLE IF EXISTS revenue_by_region;
-- DROP TABLE IF EXISTS orders;
-- DROP TABLE IF EXISTS customers;
