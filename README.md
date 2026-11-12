# AWS Event-Driven Security-Group Auto-Remediation (Lab)

This companion starter project implements the Terraform + AWS Config + CloudTrail + EventBridge + Lambda + DynamoDB architecture described in the *CB Speed Run Project* reference PDF. It creates a new **unattached** demo security group, detects public ingress on SSH/RDP, selectively removes public CIDRs, and writes an audit receipt.

> **Warning:** Disposable learning environment only. Never attach the test group to production resources. This setup can incur AWS charges. AWS services were **not** deployed or integration-tested as part of creating this starter package; review all code and permissions in your own authorized lab account before running.

## Quick start (Windows PowerShell)

Follow `WINDOWS_BONUS_GUIDE.md` for installation, credentials, GitHub upload, AWS Config preflight, deployment, verification, screenshots, and cleanup.

```powershell
$env:AWS_PROFILE = "cb-speed-run"
aws sts get-caller-identity
aws configservice describe-configuration-recorders --region us-east-1
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out demo.tfplan
terraform apply demo.tfplan
```

If your account already has a customer-managed AWS Config recorder in us-east-1, use `terraform plan -var="enable_config_recorder=false" -out demo.tfplan` instead and use the same variable at destroy time.

## Files

- `main.tf`, `variables.tf`, `outputs.tf`: Terraform IaC
- `src/remediate.py`: Python Lambda handler, limited to the auto-created demo SG
- `src/broken_event_test.json`: example Config event structure
- `scripts/verify.sh`: optional Git Bash test runner
- `scripts/cleanup.sh`: optional Git Bash cleanup helper
- `.gitignore`: guards local Terraform state and generated ZIP from Git commits

## Changes made compared with the PDF code

- Kept the overall dual-trigger architecture, on-demand DynamoDB ledger, Config rule, CloudTrail, test SG, and Lambda remediation concept.
- Added a safeguard that the Lambda only acts on the Terraform-created test security group.
- Recognizes common nested AWS Config event resource-ID paths.
- Uses a named audit table derived from the randomly suffixed prefix.
- Avoids prescribing a hard-coded five-second response SLO; event delivery is asynchronous.
- Scoped write actions to the demo security-group ARN in the Lambda role; `DescribeSecurityGroups` requires `*`.

**Notice:** `INCOMING_SSH_DISABLED` may flag the legitimate internal SSH rule as non-compliant, whereas the Lambda only removes public CIDRs. This is an intentional distinction between the PDF's managed-rule choice and the Lambda's narrower exposure policy.
