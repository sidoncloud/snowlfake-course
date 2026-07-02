# =============================================================================
# LAB - Transform Data with the Snowpark DataFrame API
# Section 7: Snowpark, Data Engineering in Python
#
# Run this as a local Python script.
#   pip install snowflake-snowpark-python
# Fill in your account and password below, then run:  python snowpark-dataframe.py
# =============================================================================

from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, sum as sum_, count as count_

# 1. A Session is your connection into Snowflake. Fill in your own account and
#    password. Never commit a real password; use a placeholder like this.
connection_parameters = {
    "account":   "<your_account>",     # e.g. iishysn-bdc54260
    "user":      "<your_user>",
    "password":  "<your_password>",
    "role":      "ACCOUNTADMIN",
    "warehouse": "COURSE_WH",
    "database":  "SNOWFLAKE_LABS",
    "schema":    "SNOWPARK",
}
session = Session.builder.configs(connection_parameters).create()

# Make sure the schema exists, then point the session at it.
session.sql("CREATE DATABASE IF NOT EXISTS SNOWFLAKE_LABS").collect()
session.sql("CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_LABS.SNOWPARK").collect()
session.use_schema("SNOWFLAKE_LABS.SNOWPARK")

# 2. Seed two small tables so the lab is self-contained.
session.sql("""
    CREATE OR REPLACE TABLE customers (
        customer_id INT, name STRING, region STRING)""").collect()
session.sql("""
    INSERT INTO customers VALUES
        (1,'Ava','WEST'),(2,'Liam','EAST'),(3,'Mia','WEST'),
        (4,'Noah','EAST'),(5,'Ivy','SOUTH')""").collect()
session.sql("""
    CREATE OR REPLACE TABLE orders (
        order_id INT, customer_id INT, amount NUMBER(10,2), status STRING)""").collect()
session.sql("""
    INSERT INTO orders VALUES
        (101,1,120.00,'COMPLETED'),(102,1,80.00,'COMPLETED'),
        (103,2,200.00,'COMPLETED'),(104,2,50.00,'CANCELLED'),
        (105,3,300.00,'COMPLETED'),(106,4,150.00,'COMPLETED'),
        (107,4,90.00,'COMPLETED'),(108,5,60.00,'CANCELLED'),
        (109,5,220.00,'COMPLETED'),(110,3,40.00,'COMPLETED')""").collect()

# 3. Read a table into a DataFrame. This defines the DataFrame; it does not run.
orders = session.table("orders")
customers = session.table("customers")

# count() is an action, so this line is the first thing that actually runs SQL.
print("orders row count:", orders.count())

# 4. Chain transformations. filter, join, group_by, agg all stay lazy: they only
#    build a plan. Nothing executes here.
completed = orders.filter(col("status") == "COMPLETED")
revenue_by_region = (
    completed.join(customers, completed["customer_id"] == customers["customer_id"])
             .group_by(customers["region"])
             .agg(sum_(completed["amount"]).alias("revenue"),
                  count_(completed["order_id"]).alias("order_count"))
             .sort(col("revenue").desc())
)

# 5. show() is an action. It triggers pushdown: the whole plan compiles to one
#    SQL query that runs on the warehouse, and the result comes back.
print("=== revenue_by_region ===")
revenue_by_region.show()

# 6. Inspect the SQL Snowpark generated. Your Python was a builder; this is the
#    query the warehouse actually ran.
print("=== pushdown SQL ===")
for q in revenue_by_region.queries["queries"]:
    print(q)

# 7. Persist the result. save_as_table is an action too, and it writes the output
#    of the plan straight into a Snowflake table without the data leaving Snowflake.
revenue_by_region.write.mode("overwrite").save_as_table("revenue_by_region")
print("saved rows:", session.table("revenue_by_region").count())

session.close()

# Cleanup (optional, run this when you are done to remove what the lab created):
# session.sql("DROP TABLE IF EXISTS revenue_by_region").collect()
# session.sql("DROP TABLE IF EXISTS orders").collect()
# session.sql("DROP TABLE IF EXISTS customers").collect()
