# Capstone Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an ELT data pipeline for NZ electricity generation data (CSVs to GCS to BigQuery via Kestra and dbt).

**Architecture:** Terraform provisions GCS and BigQuery. A Kestra flow handles batch downloading of CSVs and uploading them to GCS. BigQuery external tables read from GCS. dbt-core handles the transformations inside BigQuery.

**Tech Stack:** Kestra, Python, Google Cloud Storage (GCS), BigQuery, dbt Core, Terraform.

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

### Task 2: Kestra Flow for Ingestion
**Files:**
- Create: `kestra/flows/ingest_generation_data.yml`

**Step 1: Write Kestra Yaml**
Write a flow that uses a `io.kestra.plugin.scripts.python.Script` task to download https://www.emi.ea.govt.nz/Wholesale/Datasets/Generation/Generation_MD/YYYYMM_Generation_MD.csv for recent backfill months, and uploads to GCS using `io.kestra.plugin.gcp.gcs.Upload`.

**Step 2: Validate Flow**
Run: (Wait for user to start Kestra locally and load flow)
Expected: Flow loads successfully or passes lint.

**Step 3: Commit**
```bash
git add kestra/
git commit -m "feat: add kestra ingestion flow"
```

### Task 3: Kestra Flow for BigQuery External Table
**Files:**
- Modify: `kestra/flows/ingest_generation_data.yml:add-bq-task`

**Step 1: Add BigQuery Task**
Add an `io.kestra.plugin.gcp.bigquery.Query` task to create/replace an external table pointing to the GCS bucket `raw/generation_md/*.csv`.

**Step 2: Commit**
```bash
git add kestra/flows/ingest_generation_data.yml
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
