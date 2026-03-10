variable "project_id" {
  description = "The GCP Project ID"
  type        = string
}

variable "region" {
  description = "The GCP Region"
  type        = string
  default     = "australia-southeast1"
}

variable "gcs_bucket_name" {
  description = "The name of the GCS bucket for the data lake"
  type        = string
}

variable "bq_dataset_id" {
  description = "The ID of the BigQuery dataset"
  type        = string
  default     = "nz_electricity_generation"
}

variable "location" {
  description = "The GCP location for resources"
  type        = string
  default     = "australia-southeast1"
}
