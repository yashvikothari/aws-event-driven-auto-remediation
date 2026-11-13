AWS Event-Driven Auto Remediation

A hands-on AWS security project that detects publicly exposed SSH/RDP access in Security Groups and automatically removes the risky rules.

The project uses AWS Config, CloudTrail, EventBridge, and Lambda to detect and respond to security changes. Every remediation is recorded in DynamoDB for auditing.

How It Works
AWS Config monitors Security Group compliance.
CloudTrail records changes made to Security Groups.
EventBridge routes relevant events to Lambda.
Lambda checks the affected Security Group.
Public SSH/RDP access is removed while legitimate internal access is preserved.
The Security Group is tagged and the remediation details are stored in DynamoDB.

CloudTrail and AWS Config data are also delivered to S3, while Lambda execution logs are available in CloudWatch.


## AWS Services Used

| Service | Purpose |
|---|---|
| AWS Config | Monitors Security Group compliance |
| CloudTrail | Records AWS API activity |
| EventBridge | Routes security events |
| Lambda | Handles automatic remediation |
| EC2 Security Groups | Resources being monitored |
| DynamoDB | Stores remediation audit records |
| S3 | Stores security telemetry |
| CloudWatch | Stores Lambda execution logs |
| Terraform | Provisions AWS infrastructure |

## Project Structure

```text
aws-event-driven-auto-remediation/
│
├── main.tf
├── variables.tf
├── outputs.tf
├── README.md
│
├── src/
│   ├── remediate.py
│   └── broken_event_test.json
│
└── scripts/
    ├── verify.sh
    └── cleanup.sh
```

## Deployment

### Prerequisites

- AWS account with the required permissions
- AWS CLI configured
- Terraform installed
- Git installed

### Deploy

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

### Cleanup

```bash
terraform destroy
```
