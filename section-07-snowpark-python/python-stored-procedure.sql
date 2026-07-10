-- =============================================================================
-- LAB - Deploy and Schedule a Python Stored Procedure
-- Section 7: Snowpark, Data Engineering in Python
--
-- We build a real daily sales-analytics refresh as a Snowpark Python stored
-- procedure, then deploy it as a permanent object and schedule it as a task that
-- runs server-side with nobody at the keyboard.
--
-- The procedure works over the SNOWFLAKE_SAMPLE_DATA TPCH_SF1 data: ORDERS is
-- about 1.5 million rows, LINEITEM about 6 million. It takes parameters, joins
-- five tables, computes business metrics, MERGEs the result into a curated
-- summary table so re-runs update in place, writes an audit row every run, and
-- returns a status string. Run it in a Snowsight worksheet. No credentials needed.
-- =============================================================================

-- 1. A home for the lab. A dedicated database and schema keep everything isolated.
CREATE DATABASE IF NOT EXISTS SNOWPARK_SPROC_LAB;
CREATE SCHEMA IF NOT EXISTS SNOWPARK_SPROC_LAB.ANALYTICS;
USE SCHEMA SNOWPARK_SPROC_LAB.ANALYTICS;
USE WAREHOUSE COURSE_WH;

-- 2. The curated output tables the procedure writes to. Creating them up front
--    means the MERGE has a target to upsert into, and the audit table has
--    somewhere to append a run-log row.
CREATE TABLE IF NOT EXISTS SALES_SUMMARY (
    region          STRING,
    market_segment  STRING,
    order_count     NUMBER,
    net_revenue     NUMBER(18,2),
    discount_given  NUMBER(18,2),
    avg_order_value NUMBER(18,2),
    late_ship_rate  NUMBER(6,4),
    refreshed_at    TIMESTAMP_NTZ
);

CREATE TABLE IF NOT EXISTS TOP_CUSTOMERS (
    region         STRING,
    market_segment STRING,
    customer_name  STRING,
    net_revenue    NUMBER(18,2),
    revenue_rank   NUMBER,
    refreshed_at   TIMESTAMP_NTZ
);

CREATE TABLE IF NOT EXISTS REFRESH_AUDIT (
    run_id         STRING,
    run_ts         TIMESTAMP_NTZ,
    market_segment STRING,
    min_order_date DATE,
    segment_rows   NUMBER,
    customer_rows  NUMBER,
    status         STRING
);

-- 3. The procedure. LANGUAGE PYTHON with a Snowpark handler named run. The three
--    parameters make it reusable: which market segment to refresh (or ALL), how
--    far back to look, and how many top customers to rank per region and segment.
CREATE OR REPLACE PROCEDURE REFRESH_SALES_ANALYTICS(
        TARGET_SEGMENT STRING, MIN_ORDER_DATE DATE, TOP_N INT)
    RETURNS STRING
    LANGUAGE PYTHON
    RUNTIME_VERSION = '3.11'
    PACKAGES = ('snowflake-snowpark-python')
    HANDLER = 'run'
AS
$$
import uuid
from snowflake.snowpark.functions import (
    col, sum as sum_, count as count_, avg, iff, when_matched, when_not_matched,
    current_timestamp, lit, round as round_, rank, upper,
)
from snowflake.snowpark import Window

def run(session, target_segment, min_order_date, top_n):
    run_id = str(uuid.uuid4())
    src = "SNOWFLAKE_SAMPLE_DATA.TPCH_SF1"
    try:
        # Point DataFrames at the five source tables. Everything stays lazy.
        orders   = session.table(f"{src}.ORDERS")
        lineitem = session.table(f"{src}.LINEITEM")
        customer = session.table(f"{src}.CUSTOMER")
        nation   = session.table(f"{src}.NATION")
        region   = session.table(f"{src}.REGION")

        # Apply the parameters. A date threshold on orders, and an optional
        # market-segment filter (pass ALL to refresh every segment).
        orders = orders.filter(col("O_ORDERDATE") >= min_order_date)
        cust = customer
        if target_segment is not None and target_segment != "ALL":
            cust = cust.filter(upper(col("C_MKTSEGMENT")) == upper(lit(target_segment)))

        # Join line items up to orders, customers, nations, and regions.
        joined = (
            lineitem
            .join(orders, lineitem["L_ORDERKEY"] == orders["O_ORDERKEY"])
            .join(cust, orders["O_CUSTKEY"] == cust["C_CUSTKEY"])
            .join(nation, cust["C_NATIONKEY"] == nation["N_NATIONKEY"])
            .join(region, nation["N_REGIONKEY"] == region["R_REGIONKEY"])
        )

        # Business measures at the line level. Net revenue is price after the
        # discount; discount given is the money left on the table; a line is late
        # when it was received after it was committed.
        net_line  = col("L_EXTENDEDPRICE") * (lit(1) - col("L_DISCOUNT"))
        disc_line = col("L_EXTENDEDPRICE") * col("L_DISCOUNT")
        is_late   = iff(col("L_RECEIPTDATE") > col("L_COMMITDATE"), lit(1), lit(0))
        enriched = (joined
            .with_column("NET_LINE", net_line)
            .with_column("DISC_LINE", disc_line)
            .with_column("IS_LATE", is_late))

        # Roll up to one row per region and market segment.
        seg = (enriched.group_by(col("R_NAME"), col("C_MKTSEGMENT"))
            .agg(
                count_(col("O_ORDERKEY")).as_("ORDER_COUNT"),
                round_(sum_(col("NET_LINE")), 2).as_("NET_REVENUE"),
                round_(sum_(col("DISC_LINE")), 2).as_("DISCOUNT_GIVEN"),
                round_(avg(col("O_TOTALPRICE")), 2).as_("AVG_ORDER_VALUE"),
                round_(avg(col("IS_LATE")), 4).as_("LATE_SHIP_RATE"),
            )
            .select(
                col("R_NAME").as_("REGION"),
                col("C_MKTSEGMENT").as_("MARKET_SEGMENT"),
                "ORDER_COUNT", "NET_REVENUE", "DISCOUNT_GIVEN",
                "AVG_ORDER_VALUE", "LATE_SHIP_RATE",
            )
            .with_column("REFRESHED_AT", current_timestamp()))
        seg.cache_result()
        segment_rows = seg.count()

        # Incremental upsert. MERGE updates a segment row in place if it already
        # exists, and inserts it if it is new. A scheduled job re-runs constantly,
        # so we want it to refresh rows, not pile up duplicates.
        target = session.table("SALES_SUMMARY")
        target.merge(
            seg,
            (target["REGION"] == seg["REGION"]) &
            (target["MARKET_SEGMENT"] == seg["MARKET_SEGMENT"]),
            [
                when_matched().update({
                    "ORDER_COUNT": seg["ORDER_COUNT"],
                    "NET_REVENUE": seg["NET_REVENUE"],
                    "DISCOUNT_GIVEN": seg["DISCOUNT_GIVEN"],
                    "AVG_ORDER_VALUE": seg["AVG_ORDER_VALUE"],
                    "LATE_SHIP_RATE": seg["LATE_SHIP_RATE"],
                    "REFRESHED_AT": seg["REFRESHED_AT"],
                }),
                when_not_matched().insert({
                    "REGION": seg["REGION"],
                    "MARKET_SEGMENT": seg["MARKET_SEGMENT"],
                    "ORDER_COUNT": seg["ORDER_COUNT"],
                    "NET_REVENUE": seg["NET_REVENUE"],
                    "DISCOUNT_GIVEN": seg["DISCOUNT_GIVEN"],
                    "AVG_ORDER_VALUE": seg["AVG_ORDER_VALUE"],
                    "LATE_SHIP_RATE": seg["LATE_SHIP_RATE"],
                    "REFRESHED_AT": seg["REFRESHED_AT"],
                }),
            ],
        )

        # Top-N customers by net revenue within each region and segment, using a
        # window rank. This is the "who are our best accounts" cut of the same data.
        cust_rev = (enriched.group_by(col("R_NAME"), col("C_MKTSEGMENT"), col("C_NAME"))
            .agg(round_(sum_(col("NET_LINE")), 2).as_("NET_REVENUE")))
        w = (Window.partition_by(col("R_NAME"), col("C_MKTSEGMENT"))
                   .order_by(col("NET_REVENUE").desc()))
        ranked = (cust_rev
            .with_column("REVENUE_RANK", rank().over(w))
            .filter(col("REVENUE_RANK") <= top_n)
            .select(
                col("R_NAME").as_("REGION"),
                col("C_MKTSEGMENT").as_("MARKET_SEGMENT"),
                col("C_NAME").as_("CUSTOMER_NAME"),
                "NET_REVENUE", "REVENUE_RANK",
            )
            .with_column("REFRESHED_AT", current_timestamp()))
        ranked.cache_result()
        customer_rows = ranked.count()
        ranked.write.mode("overwrite").save_as_table("TOP_CUSTOMERS")

        # Audit log. One row per run: who ran, with which parameters, how much it
        # processed, and that it succeeded.
        audit = session.create_dataframe(
            [[run_id, str(target_segment), str(min_order_date),
              int(segment_rows), int(customer_rows), "SUCCESS"]],
            schema=["RUN_ID", "MARKET_SEGMENT", "MIN_ORDER_DATE",
                    "SEGMENT_ROWS", "CUSTOMER_ROWS", "STATUS"])
        (audit.with_column("RUN_TS", current_timestamp())
              .select("RUN_ID", "RUN_TS", "MARKET_SEGMENT",
                      col("MIN_ORDER_DATE").cast("date").as_("MIN_ORDER_DATE"),
                      "SEGMENT_ROWS", "CUSTOMER_ROWS", "STATUS")
              .write.mode("append").save_as_table("REFRESH_AUDIT"))

        return (f"Refreshed {segment_rows} segment rows, ranked {customer_rows} "
                f"customers, run_id={run_id}")

    except Exception as e:
        # On failure, record a FAILED audit row so the run is never silent, then
        # re-raise so the caller and the task both see the error.
        (session.create_dataframe(
            [[run_id, str(target_segment), str(min_order_date), 0, 0,
              f"FAILED: {str(e)[:200]}"]],
            schema=["RUN_ID", "MARKET_SEGMENT", "MIN_ORDER_DATE",
                    "SEGMENT_ROWS", "CUSTOMER_ROWS", "STATUS"])
         .with_column("RUN_TS", current_timestamp())
         .select("RUN_ID", "RUN_TS", "MARKET_SEGMENT",
                 col("MIN_ORDER_DATE").cast("date").as_("MIN_ORDER_DATE"),
                 "SEGMENT_ROWS", "CUSTOMER_ROWS", "STATUS")
         .write.mode("append").save_as_table("REFRESH_AUDIT"))
        raise
$$;

-- 4. Confirm the procedure is deployed as a permanent object in the schema.
SHOW PROCEDURES LIKE 'REFRESH_SALES_ANALYTICS';

-- 5. Run it by hand once to prove it works. We call it on its own with CALL,
--    not inside a SELECT, because a procedure does work, it does not compute a
--    column. This refreshes the BUILDING segment for orders since 1997, top 5.
CALL REFRESH_SALES_ANALYTICS('BUILDING', '1997-01-01'::DATE, 5);

-- Inspect what it wrote.
SELECT region, market_segment, order_count, net_revenue, discount_given,
       avg_order_value, late_ship_rate
FROM SALES_SUMMARY ORDER BY net_revenue DESC;

SELECT region, market_segment, customer_name, net_revenue, revenue_rank
FROM TOP_CUSTOMERS ORDER BY region, market_segment, revenue_rank;

SELECT * FROM REFRESH_AUDIT ORDER BY run_ts DESC;

-- Run it a second time and watch SALES_SUMMARY stay at the same row count. The
-- MERGE updated the rows in place instead of duplicating them. That is exactly
-- the behavior a scheduled job needs.
CALL REFRESH_SALES_ANALYTICS('BUILDING', '1997-01-01'::DATE, 5);
SELECT COUNT(*) AS summary_rows FROM SALES_SUMMARY;

-- 6. Deploy it on a schedule. A task wraps the CALL and runs it server-side. We
--    schedule it daily at 6am UTC with a CRON expression. The task body is the
--    exact same CALL we just ran by hand.
CREATE OR REPLACE TASK REFRESH_SALES_TASK
    WAREHOUSE = COURSE_WH
    SCHEDULE  = 'USING CRON 0 6 * * * UTC'
AS
    CALL REFRESH_SALES_ANALYTICS('BUILDING', '1997-01-01'::DATE, 5);

-- A new task is created suspended, so it does not run yet.
SHOW TASKS LIKE 'REFRESH_SALES_TASK';

-- 7. Resume the task to make it live. From here Snowflake fires the CALL every
--    day at 6am on its own. State moves from suspended to started.
ALTER TASK REFRESH_SALES_TASK RESUME;
SHOW TASKS LIKE 'REFRESH_SALES_TASK';

-- 8. We do not want to wait until 6am, so trigger one run right now. EXECUTE TASK
--    fires the task immediately, regardless of its schedule, so we can watch it.
EXECUTE TASK REFRESH_SALES_TASK;

-- 9. Watch it run. TASK_HISTORY shows the state move through SCHEDULED, then
--    EXECUTING, then SUCCEEDED, along with the status string the procedure
--    returned. Re-run this a few times over the next minute until you see
--    SUCCEEDED.
SELECT name, state, scheduled_time, completed_time, return_value, error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'REFRESH_SALES_TASK'))
ORDER BY scheduled_time DESC
LIMIT 5;

-- Confirm the scheduled run refreshed the tables. A fresh audit row landed, and
-- the summary is still one row per region and segment.
SELECT * FROM REFRESH_AUDIT ORDER BY run_ts DESC;
SELECT COUNT(*) AS summary_rows FROM SALES_SUMMARY;

-- 10. Teardown so the task never burns credits after the lab. Suspend it first,
--     then drop it, then drop the lab database.
ALTER TASK REFRESH_SALES_TASK SUSPEND;
DROP TASK IF EXISTS REFRESH_SALES_TASK;

-- Cleanup (optional, run this when you are done to remove everything the lab created):
--   DROP DATABASE IF EXISTS SNOWPARK_SPROC_LAB;
