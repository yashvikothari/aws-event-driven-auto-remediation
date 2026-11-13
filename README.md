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

AWS Services Used
AWS Config – Monitors security compliance.
CloudTrail – Records AWS API activity.
EventBridge – Routes security events.
Lambda – Handles automatic remediation.
EC2 Security Groups – Resources being monitored and remediated.
DynamoDB – Stores remediation audit records.
S3 – Stores security telemetry.
CloudWatch – Stores Lambda execution logs.
Terraform – Provisions AWS infrastructure.
Project Structure
text
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

Deployment
Prerequisites
AWS account with the required permissions
AWS CLI configured
Terraform installed
Git

Use a separate AWS lab account and select the us-east-1 region.

Deploy
bash
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply


Review the Terraform plan before applying it.

If an existing customer-managed AWS Config recorder is already configured in the region, use:

bash
terraform plan -var="enable_config_recorder=false"
terraform apply -var="enable_config_recorder=false"

Cleanup

After testing, remove the resources created by Terraform:

bash
terraform plan -destroy
terraform destroy


If you deployed with enable_config_recorder=false, use the same variable during cleanup.

Important Note

This project is intended for learning and testing in a disposable AWS environment.

Never attach the demo Security Group to production resources.
Review IAM permissions before deployment.
AWS services may incur charges.
Do not commit AWS credentials or Terraform state files to GitHub.
