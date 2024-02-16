terraform {
  # required_version = "0.13.5"

  required_providers {
    google      = "5.16.0"
    google-beta = "5.16.0"
  }

  # The storage bucket needs to be created before it can be used here in the backend
  # backend "gcs" {
  #   bucket = "bucket-for-terraform-state"
  #   prefix = "terraform-google-firewall-rule/projects/__PROJECT_ID__"
  # }
}
