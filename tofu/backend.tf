# State is kept in a DigitalOcean Spaces bucket, which speaks the S3 API. The
# bucket was created by hand, since it can't hold its own state. Credentials
# come from AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY, holding a Spaces key.
terraform {
  backend "s3" {
    bucket = "inglesp-infra-demo-tofu-state"
    key    = "infra-demo-infra.tfstate"

    # Lock the state with a lock file next to it, so that two runs can't
    # change it at once
    use_lockfile = true

    # Required, but ignored by Spaces: the region is in the endpoint
    region = "us-east-1"

    endpoints = {
      s3 = "https://lon1.digitaloceanspaces.com"
    }

    # Skip checks that only make sense on AWS
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
  }
}
