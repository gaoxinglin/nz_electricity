# NZ Electricity Generation — Batch Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a production-grade batch ELT pipeline for NZ electricity generation data. CSVs → GCS → Spark (unpivot & clean) → GCS Parquet → BigQuery → dbt (modelling + quality tests) → Looker Studio dashboard.

**Architecture:** Terraform provisions GCS and BigQuery. An Airflow DAG handles monthly CSV download, upload to GCS, triggers a Spark batch job for heavy transformation (unpivot 48 TPs, handle daylight savings), then refreshes a BigQuery external table on the Spark output, and finally triggers dbt for semantic modelling and data quality testing.

**Tech Stack:** Python 3.11, Apache Spark (PySpark), Apache Airflow, GCP (GCS + BigQuery), dbt Core, dbt-expectations, Terraform, GitHub Actions.

> **Platform note:** GCP is used here for its free tier. The pipeline is platform-agnostic — see Design Document §2 for Snowflake / AWS / Azure alternatives.

---

### Task 1: Setup Infrastructure (Terraform)
**Files:**
- Create: `terraform/main.tf`
- Create: `terraform/variables.tf`

**Step 1: Write Terraform config**
Write the main.tf configuring the `google` provider, a `google_storage_bucket` for the datalake, and a `google_bigquery_dataset` for the warehouse.

**Step 2: Run terraform init/plan to verify**
Run: `terraform -chdir=terraform init` and `terraform -chdir=terraform plan`
Expected: Success.

**Step 3: Commit**
```bash
git add terraform/
git commit -m "chore: setup gcp terraform resources"
```

---

### Task 2: Spark Batch Processing Job
**Files:**
- Create: `spark/batch/process_generation.py`
- Create: `tests/test_spark_transforms.py`

**Step 1: Write `spark/batch/process_generation.py`**
```python
# Key logic:
# 1. Read raw CSV from GCS:
#    gs://nz-electricity/raw/generation_md/YYYYMM_Generation_MD.csv
#
# 2. Unpivot TP1–TP48 columns into rows using stack():
#    Input:  (trading_date, plant, fuel_type, TP1, TP2, ..., TP48)
#    Output: (trading_date, trading_period, plant_name, fuel_type, generation_mwh)
#
# 3. Handle daylight savings:
#    - Detect TP49/TP50 columns if present (autumn) → include
#    - If TP47/TP48 are all-null for a date (spring) → filter out
#
# 4. Type casting:
#    - trading_date → DateType
#    - generation_mwh → DoubleType (null → 0.0)
#    - trading_period → IntegerType
#
# 5. Deduplication: dropDuplicates() on (trading_date, trading_period, plant_name)
#
# 6. Write to GCS as Parquet:
#    gs://nz-electricity/processed/generation/trading_month=YYYYMM/
#    Partitioned by trading_month for idempotent overwrites
```

**Step 2: Write PySpark unit tests**
```python
# tests/test_spark_transforms.py
# - test_unpivot_tp_columns: given sample row with TP1–TP48, assert 48 output rows
# - test_daylight_savings_spring: TP47/TP48 null → filtered out
# - test_daylight_savings_autumn: TP49/TP50 present → included
# - test_deduplication: duplicate rows → deduplicated
# - test_type_casting: null generation → 0.0
```

**Step 3: Run locally**
```bash
spark-submit spark/batch/process_generation.py \
  --input gs://nz-electricity/raw/generation_md/202601_Generation_MD.csv \
  --output /tmp/processed/generation/
# Expected: Parquet files written with unpivoted records
pytest tests/test_spark_transforms.py -v
# Expected: All tests pass
```

**Step 4: Commit**
```bash
git add spark/ tests/
git commit -m "feat: spark batch job for generation data (unpivot + clean)"
```

---

### Task 3: Airflow DAG for Ingestion + Spark + dbt
**Files:**
- Create: `airflow/dags/ingest_generation_data.py`

**Step 1: Write Airflow DAG**
Write a DAG (`ingest_generation_data`) with monthly schedule that:

```python
# Task chain:
# download_csv >> upload_to_gcs >> spark_clean_transform >> create_external_table >> run_dbt
#
# 1. download_csv (PythonOperator):
#    - Download https://www.emi.ea.govt.nz/Wholesale/Datasets/Generation/Generation_MD/
#      {{ execution_date.strftime('%Y%m') }}_Generation_MD.csv
#    - Only processes the month matching execution_date (incremental)
#
# 2. upload_to_gcs (LocalFilesystemToGCSOperator / GCSHook):
#    - Upload to gs://nz-electricity/raw/generation_md/YYYYMM/
#
# 3. spark_clean_transform (BashOperator / DataprocSubmitJobOperator):
#    - spark-submit spark/batch/process_generation.py
#      --input gs://nz-electricity/raw/generation_md/YYYYMM/
#      --output gs://nz-electricity/processed/generation/trading_month=YYYYMM/
#    - Overwrites specific month partition only (idempotent)
#
# 4. create_external_table (BigQueryInsertJobOperator):
#    - CREATE OR REPLACE EXTERNAL TABLE pointing to
#      gs://nz-electricity/processed/generation/*.parquet
#
# 5. run_dbt (BashOperator):
#    - dbt run --project-dir dbt && dbt test --project-dir dbt
```

**Idempotency guarantee**: Each task operates on a single month partition. Re-running the DAG for the same month overwrites the same GCS path and refreshes the same external table — no duplicate data.

**Step 2: Validate DAG**
Run: `python airflow/dags/ingest_generation_data.py` to check for syntax/import errors.
Expected: DAG loads successfully without errors.

**Step 3: Commit**
```bash
git add airflow/
git commit -m "feat: airflow DAG with incremental load + spark + dbt"
```

---

### Task 4: dbt Setup, Staging Models, and Data Quality
**Files:**
- Create: `dbt/dbt_project.yml`
- Create: `dbt/packages.yml`
- Create: `dbt/models/staging/schema.yml`
- Create: `dbt/models/staging/stg_generation.sql`

**Step 1: Init dbt project**
```yaml
# dbt/dbt_project.yml
name: nz_electricity
version: "1.0.0"
profile: nz_electricity
model-paths: ["models"]
models:
  nz_electricity:
    staging:
      +materialized: view
    core:
      +materialized: table
```

```yaml
# dbt/packages.yml
packages:
  - package: calogica/dbt_expectations
    version: [">=0.10.0", "<0.11.0"]
```

**Step 2: Write staging model**
`stg_generation.sql`: Read from BigQuery external table on Spark-output Parquet. Add surrogate key, standardise column names.

**Step 3: Write staging schema with data quality tests**
```yaml
# dbt/models/staging/schema.yml
models:
  - name: stg_generation
    columns:
      - name: trading_date
        tests: [not_null]
      - name: trading_period
        tests:
          - not_null
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 1
              max_value: 50
      - name: fuel_type
        tests:
          - not_null
          - accepted_values:
              values: ['Gas', 'Coal', 'Hydro', 'Wind', 'Geothermal', 'Diesel', 'Wood', 'Biogas', 'Waste Heat', 'Solar']
      - name: generation_mwh
        tests:
          - not_null
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
              max_value: 10000  # upper bound sanity check
```

**Step 4: Run dbt deps + compile**
```bash
dbt deps --project-dir dbt
dbt compile --project-dir dbt
# Expected: PASS
```

**Step 5: Commit**
```bash
git add dbt/
git commit -m "feat: dbt staging models with data quality tests"
```

---

### Task 5: dbt Core Models
**Files:**
- Create: `dbt/models/core/fct_generation.sql`
- Create: `dbt/models/core/dim_plant.sql`
- Create: `dbt/models/core/schema.yml`

**Step 1: Write core models**
`dim_plant.sql`: Distinct plant_name + fuel_type pairs from staging.
`fct_generation.sql`: Final fact table with partitioning + clustering config:
```sql
{{ config(
    materialized='table',
    partition_by={
      "field": "trading_date",
      "data_type": "date",
      "granularity": "day"
    },
    cluster_by=["fuel_type"]
) }}
-- Partitioned by trading_date: dashboard queries filter by date range
-- Clustered by fuel_type: dashboard Tile 1 groups by fuel type
SELECT ...
FROM {{ ref('stg_generation') }}
```

**Step 2: Write core schema with row count check**
```yaml
# dbt/models/core/schema.yml
models:
  - name: fct_generation
    tests:
      - dbt_expectations.expect_table_row_count_to_be_between:
          min_value: 1000   # flag empty/incomplete data loads
    columns:
      - name: generation_mwh
        tests:
          - not_null
          - dbt_expectations.expect_column_values_to_be_between:
              min_value: 0
```

**Step 3: Run dbt run / test**
```bash
dbt run --project-dir dbt
dbt test --project-dir dbt
# Expected: All models created and all tests pass
```

**Step 4: Commit**
```bash
git add dbt/models/core/
git commit -m "feat: dbt core models with partitioning + quality tests"
```

---

### Task 6: Data Dictionary & Documentation
**Files:**
- Create: `docs/data_dictionary.md`

**Step 1: Write data dictionary**
Document each table's columns, types, descriptions, and partitioning rationale. Include the data lineage diagram from the Design Document.

**Step 2: Commit**
```bash
git add docs/
git commit -m "docs: add data dictionary and lineage"
```

---

### Task 7: CI/CD Pipeline Setup
**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1: Write GitHub Actions Workflow**
```yaml
name: CI Pipeline
on: [push, pull_request]
jobs:
  lint-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.11" }
      - name: Install dependencies
        run: pip install black ruff sqlfluff dbt-bigquery pyspark pytest dbt-expectations
      - name: Python formatting check
        run: black --check spark/ airflow/ tests/
      - name: Python lint
        run: ruff check spark/ airflow/ tests/
      - name: SQL lint
        run: sqlfluff lint dbt/models/ --dialect bigquery
      - name: Spark unit tests
        run: pytest tests/ -v
      - name: dbt compile
        run: dbt deps --project-dir dbt && dbt compile --project-dir dbt --profiles-dir dbt
```

**Step 2: Commit**
```bash
git add .github/
git commit -m "ci: github actions with spark tests + dbt compile"
```

---

### Task 8: Dashboard Setup (Looker Studio)

**Connecting BigQuery to Looker Studio:**
1. Open [Looker Studio](https://lookerstudio.google.com)
2. Create new report → Add data → BigQuery
3. Select: `YOUR_PROJECT_ID` → `nz_electricity` → `fct_generation`

**Tile 1 — Generation by Fuel Type (Bar Chart)**
- Dimension: `fuel_type`
- Metric: `SUM(generation_mwh)`
- Sort: Descending

**Tile 2 — Generation Trend Over Time (Line Chart)**
- Dimension: `trading_date`
- Metric: `SUM(generation_mwh)`
- Breakdown: `fuel_type`
