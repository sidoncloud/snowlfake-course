# =============================================================================
# LAB - Register the Model and Run Batch Inference with Snowpark ML
# Section 7: Snowpark, Data Engineering in Python
#
# This lab builds on the train lab (snowpark-ml-train.py). It reuses the
# DELIVERY_FEATURES table from that lab, logs the trained model into the
# Snowflake Model Registry, then runs batch inference on a warehouse and writes
# the predictions to a table. A short appendix at the end shows the older
# joblib-to-stage pattern the registry replaced.
#
#   pip install "snowflake-ml-python" pandas
#
# Credentials come from your connections.toml, so no password appears in the
# code. Create a connection named "snowcourse" (or change the name below) with:
#   snow connection add
# Prerequisite: run snowpark-ml-train.py first so DELIVERY_FEATURES exists.
# =============================================================================

from snowflake.snowpark import Session
from snowflake.ml.modeling.xgboost import XGBRegressor
from snowflake.ml.modeling.metrics import mean_absolute_error, r2_score
from snowflake.ml.registry import Registry

DATABASE = "SNOWPARK_ML_LAB"
SCHEMA = "PUBLIC"
MODEL_NAME = "DELIVERY_DELAY_MODEL"
VERSION_NAME = "V1"

# 1. Open a Session from connections.toml and reuse the warehouse, database, and
#    schema the train lab created.
session = Session.builder.config("connection_name", "snowcourse").create()
session.use_warehouse("SNOWPARK_ML_WH")
session.use_schema(f"{DATABASE}.{SCHEMA}")

# 2. Read back the features the train lab saved. Nothing is re-engineered here;
#    we reuse the exact table so the two labs stay consistent.
features_df = session.table("DELIVERY_FEATURES")

FEATURES = [
    "DISTANCE_KM", "PACKAGE_WEIGHT_KG", "PRIORITY_CODE", "HANDOFFS", "PRIOR_DELAYS",
    "DEPARTURE_HOUR", "DEPARTURE_DOW", "IS_WEEKEND", "IS_PEAK",
    "COURIER_TOTAL_ORDERS", "CUSTOMER_ORDER_SEQ",
]
LABEL = ["DELIVERY_DELAY_MINUTES"]

# 3. Train the model so we have an object to register. It is the same regressor
#    as the train lab; fit still runs on the warehouse.
train_df, test_df = features_df.random_split([0.8, 0.2], seed=42)
model = XGBRegressor(
    input_cols=FEATURES, label_cols=LABEL, output_cols=["PREDICTED_DELAY"],
    max_depth=6, n_estimators=200,
)
model.fit(train_df)

# 4. Score it so we can attach the metrics to the registered version.
predictions = model.predict(test_df)
mae = mean_absolute_error(
    df=predictions, y_true_col_names="DELIVERY_DELAY_MINUTES",
    y_pred_col_names="PREDICTED_DELAY",
)
r2 = r2_score(
    df=predictions, y_true_col_name="DELIVERY_DELAY_MINUTES",
    y_pred_col_name="PREDICTED_DELAY",
)
print(f"Trained model. MAE: {mae:.2f} minutes, R2: {r2:.3f}")

# 5. Open the Model Registry in our database and schema.
reg = Registry(session=session, database_name=DATABASE, schema_name=SCHEMA)

# 6. Log the model. If this version already exists from a previous run, remove
#    the model first so the lab is safe to re-run.
existing = [m.name for m in reg.models()]
if MODEL_NAME in existing:
    reg.delete_model(MODEL_NAME)

model_version = reg.log_model(
    model,
    model_name=MODEL_NAME,
    version_name=VERSION_NAME,
    comment="XGBoost regressor predicting delivery delay in minutes",
    metrics={"mean_absolute_error": mae, "r2_score": r2},
    sample_input_data=train_df.select(FEATURES).limit(100),
)
print(f"Registered {MODEL_NAME} version {VERSION_NAME}")

# 7. show_models lists every model in the registry with its versions. This is
#    your model catalog, versioned and governed inside Snowflake.
print(reg.show_models()[["name", "versions", "default_version_name"]])

# 8. Batch inference. We take the orders as if they were new, unscored rows,
#    keep only ORDER_ID plus the feature columns, and let the registered model
#    predict. run executes on the warehouse; nothing comes down to the client.
new_orders = features_df.select(["ORDER_ID"] + FEATURES)
scored = model_version.run(new_orders, function_name="predict")

scored.write.mode("overwrite").save_as_table("DELIVERY_PREDICTIONS")
print("DELIVERY_PREDICTIONS rows:", session.table("DELIVERY_PREDICTIONS").count())
session.table("DELIVERY_PREDICTIONS").select("ORDER_ID", "PREDICTED_DELAY").show(5)

session.close()

# =============================================================================
# APPENDIX - the old way, and why the registry replaced it
#
# Before the Model Registry, you serialized the model to a file with joblib,
# uploaded it to an internal stage with session.file.put, and to score new data
# you pulled it back with session.file.get and loaded it on the client. It works,
# but you own everything: the file naming, the versioning, the signature, and the
# runtime. There is no catalog, no metrics, and inference runs wherever you
# happen to load the file, not inside Snowflake.
#
# The registry replaced all of that. log_model versions the model, records its
# signature and metrics, and run executes prediction on a warehouse next to the
# data. For reference, the old pattern looked like this:
#
#   import joblib
#   session.sql("CREATE STAGE IF NOT EXISTS MODEL_STAGE").collect()
#   joblib.dump(model.to_xgboost(), "/tmp/model.joblib")
#   session.file.put("/tmp/model.joblib", "@MODEL_STAGE", overwrite=True)
#   # ...later, to score...
#   session.file.get("@MODEL_STAGE/model.joblib", "/tmp/")
#   loaded = joblib.load("/tmp/model.joblib")   # runs on the client, not Snowflake
# =============================================================================

# Cleanup (optional, run this when you are done to remove what the labs created):
#   DROP DATABASE IF EXISTS SNOWPARK_ML_LAB;
#   DROP WAREHOUSE IF EXISTS SNOWPARK_ML_WH;
