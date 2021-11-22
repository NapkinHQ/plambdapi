#!/usr/bin/env bash

set -ex

echo "Packaging lambda code..."
zip -r lambda.zip lambda.py 

workspace=${1:-dev}

terraform workspace select ${workspace}
terraform apply -var-file="${workspace}.tfvars"