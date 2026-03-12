# DE Zoomcamp Capstone Design Document
# NZ Electricity Generation — Batch Pipeline

---

## 1. Objective

Build a **production-grade batch ELT pipeline** to ingest, process, transform, and visualize the New Zealand electricity generation dataset from the Electricity Authority of NZ (EMI).

This project is positioned as a **Batch Processing showcase**, emphasising engineering quality: incremental loading, idempotent DAGs, Spark-based data cleansing, data quality testing, and optimised warehouse design.

---

## 2. Cloud Platform Choice

> **Note on platform selection:** This project uses **Google Cloud Platform (GCP)** — specifically GCS and BigQuery — because GCP offers a generous free tier suitable for personal portfolio projects. In a production or enterprise setting, the same architecture applies to other platforms:
> - **Snowflake** — increasingly adopted in NZ enterprises (banking, insurance, retail) as the warehouse layer, replacing BigQuery
> - **AWS** — S3 + Redshift / Athena + Glue as equivalent stack
> - **Azure** — ADLS Gen2 + Synapse Analytics / Azure Databricks, widely used in NZ government and financial sectors
>
> The pipeline design is **platform-agnostic** — Terraform modules, Airflow operators, Spark connectors, and dbt adapters can be swapped with minimal code changes.

---

## 3. Architecture Approach

The project follows a **Batch ELT** data lake architecture with Spark for heavy data processing:

```
EMI CSV Files (monthly)
        │
        ▼
┌──────────────────────┐
│  Airflow DAG         │
│  (monthly schedule)  │
│  - Download CSVs     │
│  - Upload to GCS     │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────────────────────────────────┐
│              DATA LAKE (GCS)                      │
│  gs://nz-electricity/raw/generation_md/YYYYMM/   │
│  gs://nz-electricity/processed/generation/        │
└──────────┬───────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────┐
│          SPARK BATCH (Dataproc / local)           │
│  - Read raw CSVs from GCS                        │
│  - Unpivot 48 trading periods → individual rows   │
│  - Handle daylight savings (TP46/TP50)            │
│  - Type casting, null handling, deduplication     │
│  - Write cleaned Parquet → GCS /processed/        │
└──────────┬───────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────┐
│          DATA WAREHOUSE (BigQuery)                │
│  External Table → processed Parquet               │
│  Partitioned by trading_date                      │
│  Clustered by fuel_type                           │
└──────────┬───────────────────────────────────────┘
           │ dbt transformations + data quality
           ▼
┌──────────────────────────────────────────────────┐
│          DASHBOARD (Looker Studio)                │
│  Tile 1: Generation by Fuel Type (bar chart)      │
│  Tile 2: Generation trend over time (line chart)  │
└──────────────────────────────────────────────────┘
```

### Why Spark Batch in this project?
The EMI electricity CSV files contain 48 trading period columns (TP1–TP48) per row per day. Unpivoting these into individual records, handling daylight savings adjustments (TP46 nulls in spring, TP50 present in autumn), type casting, and deduplication are transformation-heavy operations better suited to a distributed processing engine. While dbt/SQL can handle this at small scale, introducing Spark here:
1. Demonstrates **PySpark batch processing** competence as a distinct skill from the Streaming project (#2)
2. Provides a realistic processing layer pattern: **Spark for heavy ETL, dbt for semantic modelling**
3. Creates portfolio differentiation: Project 1 = Spark Batch + dbt, Project 2 = Spark Streaming + dbt

---

## 4. Infrastructure (IaC)

- **Tool**: Terraform
- **Cloud Provider**: GCP (see Section 2 for alternatives)
- **Resources**:

| Resource                 | Purpose                                     |
| ------------------------ | ------------------------------------------- |
| `google_storage_bucket`  | Data Lake — `nz-electricity-lake`           |
| `google_bigquery_dataset`| Data Warehouse — `nz_electricity`           |

---

## 5. Orchestration (Apache Airflow)

- **Tool**: Apache Airflow
- **DAG**: `ingest_generation_data` (monthly schedule, supports backfill)

| Task                     | Operator                       | Description                                              |
| ------------------------ | ------------------------------ | -------------------------------------------------------- |
| `download_csv`           | `PythonOperator`               | Download monthly CSV from EMI website                    |
| `upload_to_gcs`          | `LocalFilesystemToGCSOperator` | Upload raw CSV to `gs://nz-electricity/raw/YYYYMM/`     |
| `spark_clean_transform`  | `BashOperator` / Dataproc      | Run Spark batch job: unpivot, clean, write Parquet       |
| `create_external_table`  | `BigQueryInsertJobOperator`    | Create/refresh external table on processed Parquet       |
| `run_dbt`                | `BashOperator`                 | Run `dbt run && dbt test`                                |

### Incremental Load Strategy
- The DAG accepts `execution_date` and only processes the **corresponding month's file**.
- On backfill (`airflow dags backfill`), each run processes exactly one month — no full reloads.
- **Idempotency**: The Spark job overwrites the specific month partition in GCS (`/processed/generation/trading_month=YYYYMM/`). Re-running the same month produces identical output without duplicates.

---

## 6. Batch Processing (Apache Spark)

- **Tool**: PySpark (local mode for dev, Dataproc for cloud)
- **Job**: `spark/batch/process_generation.py`

### Processing Logic
1. **Read** raw CSV from `gs://nz-electricity/raw/generation_md/YYYYMM_Generation_MD.csv`
2. **Unpivot** columns TP1–TP48 into individual rows: `(trading_date, trading_period, plant_name, fuel_type, generation_mwh)`
3. **Handle daylight savings**:
   - Spring forward: TP47/TP48 may be null → filter out
   - Autumn fallback: TP49/TP50 may appear → include
4. **Type casting**: `trading_date` → DATE, `generation_mwh` → DOUBLE, null → 0.0
5. **Deduplication**: Drop exact duplicate rows (defensive)
6. **Write** cleaned data as Parquet to `gs://nz-electricity/processed/generation/` partitioned by `trading_month`

### Why Spark over pure SQL/dbt?
- The unpivot of 48+ columns with conditional null handling is complex in SQL but natural in PySpark using `stack()` or `melt`
- Spark provides schema enforcement and type safety at read time
- Demonstrates batch processing competence that maps to real-world NZ data engineering roles (energy sector uses Spark extensively)

---

## 7. Data Transformation (dbt Core)

dbt operates on the **already-cleaned data** in BigQuery (loaded via Spark → Parquet → External Table). Its role is **semantic modelling**, not heavy transformation.

### Staging Layer
| Model              | Description                                           |
| ------------------ | ----------------------------------------------------- |
| `stg_generation`   | Reads external table, adds surrogate keys, standardises naming |

### Core Layer
| Model              | Description                                           |
| ------------------ | ----------------------------------------------------- |
| `dim_plant`        | Plant dimension with fuel_type, plant_name            |
| `fct_generation`   | Fact table: one row per (trading_date, trading_period, plant), generation_mwh |

### Data Quality (dbt tests + dbt-expectations)
| Test                                   | Target             | Purpose                                            |
| -------------------------------------- | ------------------ | -------------------------------------------------- |
| `not_null`                             | All key columns    | No nulls in critical fields                        |
| `unique`                               | Surrogate keys     | No duplicate rows                                  |
| `accepted_values`                      | `fuel_type`        | Only known fuel types: Gas, Coal, Hydro, Wind, Geothermal, etc. |
| `dbt_expectations.expect_column_values_to_be_between` | `generation_mwh` | Generation is non-negative and within plausible bounds |
| `dbt_expectations.expect_table_row_count_to_be_between` | `fct_generation` | Each month has expected row count (flag data gaps) |

> Data quality testing with `dbt-expectations` demonstrates awareness of **data governance** — a high-priority concern in NZ financial and energy sectors.

---

## 8. Data Warehouse Optimisation

### BigQuery Table Design
```sql
-- fct_generation: partitioned + clustered
CREATE TABLE nz_electricity.fct_generation
PARTITION BY trading_date
CLUSTER BY fuel_type
AS SELECT ...
```

**Why this strategy?**
- **Partition by `trading_date`**: Dashboard queries almost always filter by date range → BigQuery scans only relevant partitions, reducing cost and latency
- **Cluster by `fuel_type`**: The primary dashboard tile (Tile 1) groups by fuel type → clustering improves co-location of related rows within partitions
- This combination optimises the two main query patterns: "generation by date range" and "generation by fuel type"

---

## 9. Visualization (Dashboard)

- **Tool**: Looker Studio (free, native BigQuery connector)
- **Connection**: Connects directly to the final BigQuery `fct_generation` and `dim_plant` models.
- **Visuals**:
  - **Tile 1**: Categorical bar chart — electricity generation distribution by Fuel Type
  - **Tile 2**: Temporal line chart — generation output trend over time (monthly/daily)

---

## 10. CI/CD & Engineering Standards

| Tool           | Purpose                                                      |
| -------------- | ------------------------------------------------------------ |
| GitHub Actions | PR checks: Black, Ruff, SQLFluff, dbt compile, dbt test     |
| pytest         | Unit tests for Spark transformation logic (PySpark)          |
| `Makefile`     | `make spark-run`, `make dbt-run`, `make test`                |

---

## 11. Data Lineage

```
EMI Website (CSV)
    → Airflow: download + upload
        → GCS /raw/ (raw CSV)
            → Spark Batch: unpivot + clean + deduplicate
                → GCS /processed/ (Parquet, partitioned by trading_month)
                    → BigQuery External Table
                        → dbt: stg_generation
                            → dbt: dim_plant + fct_generation
                                → dbt-expectations: data quality tests
                                    → Looker Studio: Dashboard
```

---

## 12. Project Repository Structure

```
nz-electricity-generation-pipeline/
├── terraform/                    # IaC — GCS, BigQuery
│   ├── main.tf
│   └── variables.tf
├── airflow/
│   └── dags/
│       └── ingest_generation_data.py
├── spark/
│   └── batch/
│       └── process_generation.py # PySpark: unpivot + clean
├── dbt/
│   ├── dbt_project.yml
│   ├── packages.yml              # dbt-expectations
│   └── models/
│       ├── staging/
│       │   ├── stg_generation.sql
│       │   └── schema.yml
│       └── core/
│           ├── dim_plant.sql
│           ├── fct_generation.sql
│           └── schema.yml        # Data quality tests
├── tests/
│   └── test_spark_transforms.py  # PySpark unit tests
├── .github/
│   └── workflows/
│       └── ci.yml
├── Makefile
├── README.md
└── docs/
    └── data_dictionary.md        # Column definitions + lineage
```

---

## 13. Technology Stack Summary

| Category             | Technology              | Reason                                    |
| -------------------- | ----------------------- | ----------------------------------------- |
| Cloud                | GCP (GCS + BigQuery)    | Free tier for portfolio; swappable (see §2)|
| IaC                  | Terraform               | Industry standard                         |
| Orchestration        | Apache Airflow          | DAG-based batch scheduling                |
| Batch Processing     | Apache Spark (PySpark)  | Heavy unpivot/cleansing at scale          |
| Data Lake            | GCS + Parquet           | Cost-effective columnar storage           |
| Data Warehouse       | BigQuery                | Serverless, partitioned + clustered       |
| Transformation       | dbt Core                | Semantic modelling layer                  |
| Data Quality         | dbt-expectations        | Automated data validation                 |
| Dashboard            | Looker Studio           | Free, native BigQuery connector           |
| CI/CD                | GitHub Actions           | Automated quality gates                   |
| Language             | Python 3.11             | Primary development language              |
