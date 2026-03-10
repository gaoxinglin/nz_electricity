terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 4.51.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# GCS Bucket for Data Lake (Raw and Processed data)
resource "google_storage_bucket" "data_lake" {
  name          = var.gcs_bucket_name
  location      = var.location
  force_destroy = true # Good for learning projects, allows deleting bucket even if not empty

  # Set storage class
  storage_class = "STANDARD"

  # Enable Uniform Bucket-Level Access (UBLA) - often required by GCP org policies
  uniform_bucket_level_access = true

  public_access_prevention = "enforced"
}

# BigQuery Dataset for Data Warehouse
resource "google_bigquery_dataset" "dataset" {
  dataset_id = var.bq_dataset_id
  location   = var.location

  labels = {
    env = "dev"
  }
}
