# Snowflake — Build & Architect Data Pipelines on AWS

Source code for the Udemy course. Each file is a SQL worksheet you run top to bottom
in Snowsight.

## Setup

- A Snowflake trial account on **AWS**, region **US East (N. Virginia) / us-east-1**.
- Use the **ACCOUNTADMIN** role and the default **COMPUTE_WH** warehouse (the labs
  create their own warehouse, `COURSE_WH`, in Section 2).
- Open each `.sql` file in a Snowsight worksheet and run the statements in order.

## Contents

### Section 2 — Architecture & Fundamentals
- `section-02-architecture-fundamentals/L10-warehouses-resource-monitors.sql`
  Create a warehouse, resize it, see Standard vs Snowpark-optimized warehouse types,
  set a resource monitor, and read your consumption.

### Section 3 — Tables, Views & Semi-Structured Data
- `section-03-tables-views-semistructured/L12-create-tables-load-data.sql`
  Create permanent / transient tables and load a small retail dataset. Builds the
  `SNOWFLAKE_LABS.RETAIL` schema used by the later labs.
- `section-03-tables-views-semistructured/L14-views.sql`
  Standard, materialized, and secure views. (Run L12 first.)
- `section-03-tables-views-semistructured/L16-json-flatten.sql`
  Query JSON in a VARIANT column with dot notation, casting, and LATERAL FLATTEN.
- `section-03-tables-views-semistructured/L18-time-travel-cloning.sql`
  Recover data with Time Travel, UNDROP a table, and zero-copy clone. (Run L12 first.)

## Run order

Section 2 first (it creates `COURSE_WH`), then in Section 3 run **L12 before L14 and L18**.
