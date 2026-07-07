# =============================================================================
# LAB - Feature Engineering and Train a Model with Snowpark ML
# Section 7: Snowpark, Data Engineering in Python
#
# We build features from two related tables with the Snowpark DataFrame API
# (join, time features, window functions), then train an XGBoost regressor with
# the Snowpark ML modeling API. Training runs on a Snowflake warehouse, next to
# the data. The engineered features are saved to a table for the next lab.
#
#   pip install "snowflake-ml-python" pandas
#
# Credentials come from your connections.toml, so no password appears in the
# code. Create a connection named "snowcourse" (or change the name below) with:
#   snow connection add
# Dataset: orders.csv and order_logistics.csv from this section's datasets folder.
# =============================================================================

import pandas as pd
from snowflake.snowpark import Session, Window
from snowflake.snowpark.functions import (
    col, to_timestamp, date_part, when, iff, row_number, count,
)
from snowflake.ml.modeling.xgboost import XGBRegressor
from snowflake.ml.modeling.metrics import mean_absolute_error, r2_score

# Point this at the datasets folder you downloaded with the course.
DATA_DIR = "datasets"

# 1. A Session is your connection into Snowflake. The connection details live in
#    your connections.toml, so nothing sensitive shows up here.
session = Session.builder.config("connection_name", "snowcourse").create()

# 2. Give the lab its own warehouse, database, and schema so it stays isolated.
session.sql("""
    CREATE WAREHOUSE IF NOT EXISTS SNOWPARK_ML_WH
        WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE
""").collect()
session.sql("CREATE DATABASE IF NOT EXISTS SNOWPARK_ML_LAB").collect()
session.sql("CREATE SCHEMA IF NOT EXISTS SNOWPARK_ML_LAB.PUBLIC").collect()
session.use_warehouse("SNOWPARK_ML_WH")
session.use_schema("SNOWPARK_ML_LAB.PUBLIC")

# 3. Load the two CSV files into Snowflake tables. write_pandas creates the table
#    and uploads the rows for us.
orders_pd = pd.read_csv(f"{DATA_DIR}/orders.csv")
logistics_pd = pd.read_csv(f"{DATA_DIR}/order_logistics.csv")
session.write_pandas(orders_pd, "ORDERS", auto_create_table=True, overwrite=True)
session.write_pandas(logistics_pd, "ORDER_LOGISTICS", auto_create_table=True, overwrite=True)

orders = session.table("ORDERS")
logistics = session.table("ORDER_LOGISTICS")

# 4. Feature engineering, all pushed down to the warehouse.
#    4a. Join the two tables on ORDER_ID. Passing the column name does a natural
#        join and keeps a single ORDER_ID column.
df = orders.join(logistics, ["ORDER_ID"], "inner")

#    4b. Turn the order timestamp string into a real timestamp, then pull
#        calendar features out of it.
df = df.with_column("ORDER_TS", to_timestamp(col("ORDER_TS"), "YYYY-MM-DD HH24:MI:SS"))
df = (
    df.with_column("DEPARTURE_HOUR", date_part("hour", col("ORDER_TS")))
      .with_column("DEPARTURE_DOW", date_part("dayofweek", col("ORDER_TS")))
      .with_column("IS_WEEKEND", iff(date_part("dayofweek", col("ORDER_TS")).isin([0, 6]), 1, 0))
      .with_column("IS_PEAK", iff((col("DEPARTURE_HOUR") >= 17) & (col("DEPARTURE_HOUR") <= 20), 1, 0))
)

#    4c. Encode the priority text as a number the model can use.
df = df.with_column(
    "PRIORITY_CODE",
    when(col("PRIORITY") == "STANDARD", 0).when(col("PRIORITY") == "EXPRESS", 1).otherwise(2),
)

#    4d. Window features. COURIER_TOTAL_ORDERS is how much volume each courier
#        handles; CUSTOMER_ORDER_SEQ is where this order falls in a customer's
#        history. Neither leaks the delay we are predicting.
by_courier = Window.partition_by("COURIER")
by_customer = Window.partition_by("CUSTOMER_ID").order_by("ORDER_TS")
df = (
    df.with_column("COURIER_TOTAL_ORDERS", count("*").over(by_courier))
      .with_column("CUSTOMER_ORDER_SEQ", row_number().over(by_customer))
)

FEATURES = [
    "DISTANCE_KM", "PACKAGE_WEIGHT_KG", "PRIORITY_CODE", "HANDOFFS", "PRIOR_DELAYS",
    "DEPARTURE_HOUR", "DEPARTURE_DOW", "IS_WEEKEND", "IS_PEAK",
    "COURIER_TOTAL_ORDERS", "CUSTOMER_ORDER_SEQ",
]
LABEL = ["DELIVERY_DELAY_MINUTES"]

# 5. Save the engineered features so the next lab can reuse them.
features_df = df.select(["ORDER_ID"] + FEATURES + LABEL)
features_df.write.mode("overwrite").save_as_table("DELIVERY_FEATURES")
print("DELIVERY_FEATURES rows:", session.table("DELIVERY_FEATURES").count())

# 6. Split into train and test, then train the model. The modeling API takes
#    input_cols, label_cols, and output_cols, and fit runs on the warehouse.
train_df, test_df = features_df.random_split([0.8, 0.2], seed=42)
model = XGBRegressor(
    input_cols=FEATURES, label_cols=LABEL, output_cols=["PREDICTED_DELAY"],
    max_depth=6, n_estimators=200,
)
model.fit(train_df)

# 7. Predict on the held-out rows and score the model.
predictions = model.predict(test_df)
mae = mean_absolute_error(
    df=predictions, y_true_col_names="DELIVERY_DELAY_MINUTES",
    y_pred_col_names="PREDICTED_DELAY",
)
r2 = r2_score(
    df=predictions, y_true_col_name="DELIVERY_DELAY_MINUTES",
    y_pred_col_name="PREDICTED_DELAY",
)
print(f"Mean Absolute Error: {mae:.2f} minutes")
print(f"R2 score: {r2:.3f}")

session.close()

# Cleanup (optional, run this when you are done to remove what the lab created):
#   DROP DATABASE IF EXISTS SNOWPARK_ML_LAB;
#   DROP WAREHOUSE IF EXISTS SNOWPARK_ML_WH;
