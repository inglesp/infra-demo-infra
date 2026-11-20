# State is kept in a GCS bucket, which was created by hand, since it can't hold
# its own state. Credentials come from Application Default Credentials. GCS
# locks the state itself, with a lock object next to it, so that two runs can't
# change it at once.
terraform {
  backend "gcs" {
    bucket = "inglesp-infra-demo-gcp-tofu-state"
    prefix = "infra-demo-infra"
  }
}
