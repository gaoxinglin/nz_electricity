# DE Zoomcamp Capstone Design Document

## Objective
Build an end-to-end data pipeline to ingest, store, transform, and visualize the New Zealand electricity generation dataset from the Electricity Authority of NZ (EMI).

## Architecture Approach
The project will follow a classic Batch ELT (Extract, Load, Transform) data lake architecture.

## Infrastructure (IaC)
- **Tool**: Terraform
- **Cloud Provider**: Google Cloud Platform (GCP)
- **Resources**:
  - Google Cloud Storage (GCS) Bucket (Data Lake)
  - BigQuery Dataset (Data Warehouse)

## Orchestration (Ingestion & Execution)
- **Tool**: Kestra
- **Workflow**:
  1. A Python-based Kestra task downloads monthly CSV files from the EMI website.
  2. The files are uploaded to the GCS bucket (`/raw/generation_md/`).
  3. Kestra triggers BigQuery to create/update an External Table pointing to the GCS CSVs.
  4. Kestra triggers the dbt transformation jobs.

## Data Transformation
- **Tool**: dbt Core
- **Staging Layer (`stg_generation`)**:
  - Connects to the BigQuery external table.
  - Cleans data types and standardizes column names.
- **Core Layer (`fct_generation` / `dim_plant`)**:
  - Unpivots the 48 daily trading periods into individual records or aggregates them daily.
  - Enriches the data with plant metadata (e.g., Fuel type).

## Visualization (Dashboard)
- **Tool**: Power BI
- **Connection**: Connects directly to the final BigQuery models.
- **Visuals**:
  - Tile 1: Categorical distribution of electricity generation by Fuel Type.
  - Tile 2: Temporal line chart showing generation output over time.
