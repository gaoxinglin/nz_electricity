# Capstone Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an ELT data pipeline for NZ electricity generation data (CSVs to GCS to BigQuery via Airflow and dbt).

**Architecture:** Terraform provisions GCS and BigQuery. An Airflow DAG handles batch downloading of CSVs and uploading them to GCS. BigQuery external tables read from GCS. dbt-core handles the transformations inside BigQuery. GitHub Actions handles CI/CD checks (linting, dbt compile).

**Tech Stack:** Apache Airflow, Python, Google Cloud Storage (GCS), BigQuery, dbt Core, Terraform, GitHub Actions.

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

### Task 2: Airflow DAG for Ingestion
**Files:**
- Create: `airflow/dags/ingest_generation_data.py`

**Step 1: Write Airflow DAG**
Write a DAG that uses PythonOperator to download https://www.emi.ea.govt.nz/Wholesale/Datasets/Generation/Generation_MD/YYYYMM_Generation_MD.csv for recent backfill months, and uploads to GCS using LocalFilesystemToGCSOperator or GCSHook.

**Step 2: Validate DAG**
Run: `python airflow/dags/ingest_generation_data.py` to check for syntax/import errors.
Expected: DAG loads successfully without errors.

**Step 3: Commit**
```bash
git add airflow/
git commit -m "feat: add airflow ingestion DAG"
```

### Task 3: Airflow DAG for BigQuery External Table
**Files:**
- Modify: `airflow/dags/ingest_generation_data.py`

**Step 1: Add BigQuery Task**
Add a `BigQueryInsertJobOperator` task to the existing DAG to create/replace an external table pointing to the GCS bucket `raw/generation_md/*.csv`.

**Step 2: Commit**
```bash
git add airflow/dags/ingest_generation_data.py
git commit -m "feat: add bigquery external table integration"
```

### Task 4: dbt Setup and Staging Models
**Files:**
- Create: `dbt/dbt_project.yml`
- Create: `dbt/models/staging/schema.yml`
- Create: `dbt/models/staging/stg_generation.sql`

**Step 1: Init dbt project and write staging model**
Create the dbt models that read from the BigQuery external table, cast dates correctly, and rename columns.

**Step 2: Run dbt compile**
Run: `dbt compile --project-dir dbt`
Expected: PASS

**Step 3: Commit**
```bash
git add dbt/
git commit -m "feat: add dbt staging models"
```

### Task 5: dbt Core Models
**Files:**
- Create: `dbt/models/core/fct_generation.sql`
- Create: `dbt/models/core/schema.yml`

**Step 1: Write fact model**
Create `fct_generation.sql` to aggregate the data into a clean, queryable format for Power BI, resolving daylight savings adjustments on TP46/TP50 dates.

**Step 2: Run dbt run / test**
Run: `dbt run --project-dir dbt`
Expected: PASS

**Step 3: Commit**
```bash
git add dbt/models/core/
git commit -m "feat: add dbt core models"
```

### Task 6: CI/CD Pipeline Setup
**Files:**
- Create: `.github/workflows/ci_cd_pipeline.yml`

**Step 1: Write GitHub Actions Workflow**
Create a workflow yaml file that runs on pull request/push to main. Add steps to checkout code, setup Python, install Black, SQLFluff and dbt-bigquery, run Python linting (`black --check airflow/`), run SQL linting, and run dbt checks (`dbt compile`).

**Step 2: Commit**
```bash
git add .github/
git commit -m "ci: add github actions for linting and dbt compile"
```
