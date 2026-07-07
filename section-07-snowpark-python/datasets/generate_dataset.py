"""
Synthesize the self-contained dataset for the Snowpark ML labs (Section 7).

Domain: last-mile delivery. Two related tables so the lab can teach a real join
and window-function feature engineering:

  orders.csv          one row per order  (the "what was ordered" facts)
  order_logistics.csv one row per order  (the "how it was delivered" facts + target)

Target: DELIVERY_DELAY_MINUTES (regression). It is generated from a real signal
(distance, weight, priority, handoffs, courier bias, weekend, peak hour, prior
delays) plus gaussian noise, so a model trained on it lands a genuine R^2 instead
of learning nothing from pure random data. Deterministic (fixed seed) so the live
validation run and every student run see identical data.

Run: python3 generate_dataset.py   ->  writes orders.csv and order_logistics.csv
"""
import csv, random
from datetime import datetime, timedelta

random.seed(42)
N = 5000

REGIONS = ["NORTH", "SOUTH", "EAST", "WEST", "CENTRAL"]
PRIORITIES = ["STANDARD", "EXPRESS", "PRIORITY"]
PRIORITY_ADD = {"STANDARD": 18.0, "EXPRESS": 7.0, "PRIORITY": 0.0}  # slower to faster
COURIERS = ["SwiftRun", "MetroDash", "CityHop", "RapidoLog", "NovaShip"]
COURIER_BIAS = {"SwiftRun": -6, "MetroDash": 3, "CityHop": 11, "RapidoLog": -2, "NovaShip": 7}
WAREHOUSES = ["WH-A1", "WH-B2", "WH-C3", "WH-D4"]

start = datetime(2026, 1, 1, 6, 0, 0)

orders_rows = []
logistics_rows = []

for i in range(1, N + 1):
    order_id = f"ORD{i:06d}"
    customer_id = f"CUST{random.randint(1, 1200):05d}"
    ts = start + timedelta(minutes=random.randint(0, 150 * 24 * 60))
    region = random.choice(REGIONS)
    priority = random.choices(PRIORITIES, weights=[0.6, 0.3, 0.1])[0]
    weight = round(random.uniform(0.2, 25.0), 2)
    distance = round(random.uniform(1.0, 120.0), 1)

    courier = random.choice(COURIERS)
    warehouse = random.choice(WAREHOUSES)
    handoffs = random.randint(0, 5)
    prior_delays = random.randint(0, 8)

    hour = ts.hour
    dow = ts.weekday()               # 0=Mon .. 6=Sun
    is_weekend = 1 if dow >= 5 else 0
    is_peak = 1 if 17 <= hour <= 20 else 0

    delay = (
        8.0
        + distance * 0.09
        + weight * 1.3
        + PRIORITY_ADD[priority]
        + handoffs * 6.0
        + prior_delays * 2.2
        + is_weekend * 10.0
        + is_peak * 13.0
        + COURIER_BIAS[courier]
        + random.gauss(0, 6.0)
    )
    delay = max(0.0, round(delay, 1))

    orders_rows.append([
        order_id, customer_id, ts.strftime("%Y-%m-%d %H:%M:%S"),
        region, priority, weight, distance,
    ])
    logistics_rows.append([
        order_id, courier, warehouse, handoffs, prior_delays, delay,
    ])

with open("orders.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["ORDER_ID", "CUSTOMER_ID", "ORDER_TS", "REGION",
                "PRIORITY", "PACKAGE_WEIGHT_KG", "DISTANCE_KM"])
    w.writerows(orders_rows)

with open("order_logistics.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["ORDER_ID", "COURIER", "WAREHOUSE", "HANDOFFS",
                "PRIOR_DELAYS", "DELIVERY_DELAY_MINUTES"])
    w.writerows(logistics_rows)

print(f"wrote orders.csv and order_logistics.csv, {N} rows each")
