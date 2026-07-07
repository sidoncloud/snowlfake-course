# =============================================================================
# LAB - Transform Data with the Snowpark DataFrame API
# Section 7: Snowpark, Data Engineering in Python
#
# We put Snowpark to work against the RETAIL tables you already built back in
# Section 3: customers and orders. We filter, join, group, and aggregate, and we
# look at the SQL Snowpark generates before it runs.
#
#   pip install snowflake-snowpark-python
#
# ONE-TIME SETUP: let the Snowflake CLI create your connection so you never have
# to hand-edit a hidden config file. Install the CLI (the "snow" command):
#   pip install snowflake-cli
#
# Then run this interactive command and answer the prompts:
#   snow connection add
# It will ask for (use these values):
#   connection name  -> snowcourse
#   account          -> <your_account_identifier>
#   user             -> <your_username>
#   password         -> <your_password>
#   role             -> ACCOUNTADMIN
#   warehouse        -> COURSE_WH
#
# The CLI writes all of this to ~/.snowflake/connections.toml (locked down) for
# you. Verify it with:
#   snow connection test --connection snowcourse
#
# That connections.toml is the file config("connection_name", "snowcourse")
# reads below, so no credentials ever appear in this code.
# =============================================================================

from snowflake.snowpark import Session
from snowflake.snowpark.functions import col, sum as sum_, count as count_

# 1. A Session is your connection into Snowflake. The details live in your
#    connections.toml, so nothing sensitive shows up in this file.
session = Session.builder.config("connection_name", "snowcourse").create()
session.use_warehouse("COURSE_WH")  # change to your own warehouse name

# 2. Point at the existing RETAIL tables. session.table hands back a lazy
#    DataFrame; no data has moved yet.
orders = session.table("SNOWFLAKE_LABS.RETAIL.ORDERS")
customers = session.table("SNOWFLAKE_LABS.RETAIL.CUSTOMERS")

# 3. filter keeps the rows we want. Here we drop cancelled orders.
active_orders = orders.filter(col("STATUS") != "CANCELLED")

# 4. join brings the two DataFrames together on CUSTOMER_ID.
joined = active_orders.join(customers, ["CUSTOMER_ID"], "inner")

# 5. group_by with agg rolls the orders up to revenue and order count per country.
revenue_by_country = joined.group_by("COUNTRY").agg(
    sum_("AMOUNT").alias("TOTAL_REVENUE"),
    count_("*").alias("ORDER_COUNT"),
)

# 6. The chain is still lazy. Look at the single SQL query Snowpark compiled it
#    into. That is pushdown, from the last lecture, in action.
print("Generated SQL:")
print(revenue_by_country.queries["queries"][0])

# 7. show is an action, so this is the line that actually runs the query.
revenue_by_country.show()

# 8. One more transformation: rank customers by total spend, highest first.
top_customers = (
    active_orders.group_by("CUSTOMER_ID")
    .agg(sum_("AMOUNT").alias("SPEND"))
    .sort(col("SPEND").desc())
)
top_customers.show(5)

session.close()
