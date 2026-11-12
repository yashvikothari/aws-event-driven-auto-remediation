#!/usr/bin/env bash
set -euo pipefail
echo "Removing Terraform-managed demo infrastructure."
terraform destroy
# terraform destroy will prompt for approval; review first.
echo "Review AWS console and Billing to confirm cleanup."
