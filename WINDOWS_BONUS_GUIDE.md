# Bonus: Run the AWS Event-Driven Auto-Remediation Project from Zero on Windows

**Goal:** Build a local project in VS Code, publish the source on GitHub, authenticate with AWS, deploy using Terraform, simulate unsafe public SSH/RDP ingress on a **disposable, unattached** security group, verify automatic remediation, capture blog screenshots, and destroy the resources.

> **Scope and safety:** This is a hands-on lab, **not** an instruction to attach the test security group to any real EC2 instance. It uses billable AWS services (including AWS Config, CloudTrail, S3, Lambda, DynamoDB and CloudWatch). Use a separate training account with permissions you are authorized to use, review the Terraform plan, set a budget alert, and destroy the lab afterward. No cloud deployment was executed as part of preparing this guide. Runtime outcomes depend on your AWS account and permissions.

This walkthrough adapts the architecture and file structure in *CB Speed Run Project*, pp. 6–20, from an AWS CloudShell/KodeKloud runbook to **Windows + VS Code + GitHub + local AWS CLI**. The referenced PDF's published GitHub URL could not be opened at the time this guide was prepared; use the companion starter project or your own source files instead.

## Step 1. Install the required software

1. Create or sign into a [GitHub account](https://github.com/).
2. Install [Visual Studio Code](https://code.visualstudio.com/download).
3. Install [Git for Windows](https://git-scm.com/download/win), including Git Bash. Git installs a credential manager that can open a browser to sign you into GitHub.
4. Install [AWS CLI v2 for Windows](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) using its Windows installer.
5. Install [Terraform for Windows](https://developer.hashicorp.com/terraform/install): download the Windows AMD64 ZIP for a standard x64 PC, unzip `terraform.exe` into a folder such as `C:\Tools\Terraform`, add that folder to Windows **System Properties > Environment Variables > Path**, and restart VS Code/terminal.
6. Optionally install Python 3 to run local syntax checks of `src/remediate.py`; it is not required to deploy the Lambda function.

Open **Windows PowerShell** and verify that the programs are accessible:

```powershell
code --version
git --version
aws --version
terraform version
```

If `code` or `terraform` is not recognized, close and reopen PowerShell/VS Code after installation, and check PATH.

## Step 2. Create your project folder

Open **PowerShell** (not the Python console) and enter:

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\Documents\aws-event-driven-auto-remediation" | Out-Null
Set-Location "$HOME\Documents\aws-event-driven-auto-remediation"
code .
```

VS Code opens the new folder. In VS Code, select **Terminal > New Terminal** and make sure the terminal is **PowerShell**.

## Step 3. Add the project files in VS Code

Extract the contents of the companion `aws-event-driven-auto-remediation-starter.zip` into the folder you just created. **Copy the contents of the ZIP, not another nested top-level folder.** Or create the files using VS Code's Explorer and copy the project source from the main article/PDF.

The project should look like this:

```text
aws-event-driven-auto-remediation/
├── .gitignore
├── README.md
├── main.tf
├── variables.tf
├── outputs.tf
├── src/
│   ├── remediate.py
│   └── broken_event_test.json
└── scripts/
    ├── verify.sh
    └── cleanup.sh
```

**What these files do:**

- `main.tf` creates the AWS infrastructure.
- `variables.tf` defines the AWS Region and optional Config recorder behavior.
- `outputs.tf` prints the names and IDs needed during testing.
- `src/remediate.py` is the Python Lambda remediation logic.
- `src/broken_event_test.json` is an example AWS Config event for troubleshooting.
- `scripts/verify.sh` and `scripts/cleanup.sh` are optional **Git Bash** helpers; the Windows PowerShell commands below do not depend on them.
- `.gitignore` prevents generated Terraform state, plan files, and secrets from being committed.

> **Never put AWS access keys in `.tf`, `.py`, `.tfvars`, `README.md`, screenshots, or any file under this repository.** The `.terraform.lock.hcl` file created by `terraform init` **should** be committed; `.terraform/` and `*.tfstate*` should not.

## Step 4. Initialize Git on Windows

In the VS Code PowerShell terminal, run:

```powershell
git config --global user.name "YOUR NAME"
git config --global user.email "YOUR_GITHUB_EMAIL@example.com"
git init -b main
git status
```

Replace the example name and email with your own Git identity.

## Step 5. Create the GitHub repository and push the files

1. Open [github.com/new](https://github.com/new).
2. Repository name: `aws-event-driven-auto-remediation`.
3. Select **Public** if you want readers to see your blog's source, or **Private** while experimenting.
4. **Do not** check “Add a README,” `.gitignore`, or license: the local project already has these.
5. Click **Create repository**.

Back in VS Code, replace `YOUR_USERNAME` with your GitHub username and run:

```powershell
git add .
git commit -m "Initial AWS event-driven remediation lab"
git remote add origin https://github.com/YOUR_USERNAME/aws-event-driven-auto-remediation.git
git push -u origin main
```

If a GitHub sign-in browser window appears, authorize it. This is **GitHub authentication**, not an AWS access key. Open the repository URL in your browser and confirm that the source files are visible but no `.tfstate` or secrets are present.

For future edits:

```powershell
git add .
git commit -m "Update project documentation"
git push
```

## Step 6. Create or select your AWS account and Region

1. Sign into the [AWS Console](https://console.aws.amazon.com/).
2. Enable MFA on your account and use a **non-root** identity for day-to-day work.
3. Select **US East (N. Virginia), `us-east-1`** in the Region menu. The Terraform starter defaults to this Region.
4. Use an account/role with permissions to create and delete the resources in this lab: EC2 security groups, DynamoDB, S3, CloudTrail, AWS Config, Lambda, EventBridge, IAM roles/policies and CloudWatch Logs. In corporate accounts, ask an administrator for an approved scoped role rather than applying broad permissions yourself.
5. Check current [AWS pricing](https://aws.amazon.com/pricing/) and set up a [Budget alert](https://aws.amazon.com/aws-cost-management/aws-budgets/). Do not assume every service is free.

### Recommended: IAM Identity Center / temporary AWS credentials

If your AWS account or organization provides an Identity Center start URL, in PowerShell run:

```powershell
aws configure sso --profile cb-speed-run
aws sso login --profile cb-speed-run
$env:AWS_PROFILE = "cb-speed-run"
aws sts get-caller-identity
```

Follow the interactive prompts (start URL/issuer URL, SSO Region, authorized account/role, default Region `us-east-1`, and output `json`). A successful `get-caller-identity` result displays an account ID and assumed identity—not secret credentials.

### Alternative: create an IAM user's access keys (only if needed)

If you do **not** have Identity Center and must use static credentials for this local lab:

1. In AWS Console, open **IAM > Users** and select an existing authorized lab user, or have an administrator create one with the **necessary permissions**. Do **not** create access keys for the AWS root user.
2. Open **Security credentials > Access keys > Create access key**.
3. Choose the **Command Line Interface (CLI)** use case, acknowledge the warning, and complete the creation flow.
4. Securely save the **Access key ID** and **Secret access key**. The secret is shown only during key creation. Do not upload the downloaded CSV to GitHub or store it in the project folder.
5. In VS Code PowerShell, run:

```powershell
aws configure --profile cb-speed-run
```

When prompted, paste your AWS access key ID, your AWS secret access key, enter `us-east-1` as Region, and `json` as output format. Then run:

```powershell
$env:AWS_PROFILE = "cb-speed-run"
aws sts get-caller-identity
```

AWS CLI stores the configured profile under your Windows user profile's `.aws` folder (outside the project). Disable and delete this IAM access key when you have finished the lab. **AWS access keys and GitHub login credentials are completely different things.**

## Step 7. Run the AWS preflight checks

Run the following **PowerShell** commands:

```powershell
aws sts get-caller-identity
aws configure get region --profile cb-speed-run
aws ec2 describe-vpcs --region us-east-1 --filters Name=isDefault,Values=true --query "Vpcs[].VpcId" --output text
aws configservice describe-configuration-recorders --region us-east-1
```

**Important checks:**

- The account identity and Region must match the AWS account where you intend to deploy.
- The default VPC command should return a `vpc-...` value. The sample Terraform uses a **default VPC**; if your account does not have one, use an authorized lab Region with a default VPC or modify the Terraform to accept an existing VPC ID.
- AWS Config permits only **one customer-managed recorder per account per Region**. If the Config CLI output lists an existing customer-managed recorder, plan and apply with `-var="enable_config_recorder=false"`. Otherwise, use the default `true`. Do not delete or alter a recorder that belongs to another application or team.

## Step 8. Initialize and validate the Terraform project

Make sure the VS Code terminal is inside `aws-event-driven-auto-remediation` and that `$env:AWS_PROFILE` is set in this terminal.

```powershell
terraform init
terraform fmt -recursive
terraform validate
```

The first command downloads provider plugins and creates `.terraform.lock.hcl`. The second formats the Terraform source. You can optionally check style afterward with `terraform fmt -check -recursive`.

## Step 9. Review and deploy the infrastructure

**Case A: there was no pre-existing AWS Config recorder:**

```powershell
terraform plan -out demo.tfplan
terraform apply demo.tfplan
```

**Case B: there is already a customer-managed AWS Config recorder:**

```powershell
terraform plan -var="enable_config_recorder=false" -out demo.tfplan
terraform apply demo.tfplan
```

Read the plan before the apply. Applying a saved plan deploys the exact reviewed plan. Terraform may take several minutes depending on AWS. If you see access denied or service quota errors, fix the permission/quota issue in the authorized account and run plan/apply again. Do not create or revoke production security-group rules to bypass a demo error.

After a successful apply, capture **Screenshot 1: Terraform deployment finished**.

## Step 10. Collect your deployed resource IDs

In the same PowerShell terminal:

```powershell
$sg = terraform output -raw target_security_group_id
$table = terraform output -raw dynamodb_audit_table
$lambda = terraform output -raw lambda_function_name
$rule = terraform output -raw config_rule_name
Write-Host "Demo security group: $sg"
Write-Host "Audit table: $table"
Write-Host "Lambda: $lambda"
Write-Host "Config rule: $rule"
```

These are resource identifiers, not AWS secrets, but redact identifying account details before posting screenshots publicly if needed.

## Step 11. Inspect the safe starting state

The starter creates a **new unattached** demo security group with one legitimate corporate SSH CIDR, `10.20.0.0/16` (TCP port 22). The rule is for demonstrating that legitimate access survives remediation.

```powershell
aws ec2 describe-security-groups --group-ids $sg --region us-east-1 --query "SecurityGroups[0].IpPermissions" --output json
```

Capture **Screenshot 2: Initial security-group ingress**. The initial rule should not contain `0.0.0.0/0` for TCP 22 or 3389.

## Step 12. Intentionally introduce drift — only on the disposable group

**Do not run the next commands on any existing or attached production security group.**

```powershell
aws ec2 authorize-security-group-ingress --group-id $sg --protocol tcp --port 22 --cidr 0.0.0.0/0 --region us-east-1
aws ec2 authorize-security-group-ingress --group-id $sg --protocol tcp --port 3389 --cidr 0.0.0.0/0 --region us-east-1
```

This simulates a mistaken change that exposes SSH and RDP to the public internet. CloudTrail/EventBridge should send a matching API event to Lambda; Lambda inspects the **current** security-group rules, removes only `0.0.0.0/0` and `::/0` entries on protected ports, tags the test group, and attempts to write an audit receipt to DynamoDB.

> **Timing note:** EventBridge and AWS event delivery are asynchronous. Do not promise the change will be fixed in exactly three or five seconds; actual end-to-end timing varies. Give events time to propagate, verify by reading the current AWS resource state, and investigate logs if needed.

## Step 13. Verify remediation

After a short pause (for example 15–60 seconds), run:

```powershell
aws ec2 describe-security-groups --group-ids $sg --region us-east-1 --query "SecurityGroups[0].{Ingress:IpPermissions,Tags:Tags}" --output json
```

**Expected result:** the public SSH and RDP entries are gone; the original `10.20.0.0/16` SSH entry remains. The test SG may have the `AutoRemediated`, `LastRemediatedAt`, and `RemediationSource` tags.

Capture **Screenshot 3: Remediated ingress and tags**.

A note about the sample AWS Config rule: `INCOMING_SSH_DISABLED` can flag an SSH rule even when it is not public. The Lambda's removal criterion is intentionally narrower: it removes **only** public CIDRs for protected ports. Do not equate every Config NON_COMPLIANT flag with publicly exposed SSH.

## Step 14. Inspect the DynamoDB audit receipt

```powershell
aws dynamodb scan --table-name $table --region us-east-1 --limit 10 --output json
```

Look for `AuditId`, `SecurityGroupId`, `TriggerSource`, `ViolatingActor`, `RevokedPermissions`, `RemediatedAt`, and `ExpiresAt`. The sample uses conditional writes to avoid overwriting a receipt with the same ID; **this is application-level write-once behavior, not a guarantee against administrators deleting DynamoDB data**.

Capture **Screenshot 4: DynamoDB audit record**.

## Step 15. Inspect the Lambda logs and troubleshooting payload

```powershell
aws logs tail "/aws/lambda/$lambda" --since 15m --region us-east-1 --format short
```

Look for `REMEDIATED`, `IDEMPOTENT_SKIP`, or an exception. You can also open **AWS Console > CloudWatch > Logs > Log groups > `/aws/lambda/<function-name>`**.

Capture **Screenshot 5: Lambda structured log events**.

If you are documenting the PDF's parser bug, open `src/broken_event_test.json` in VS Code and show how the code extracts a group ID from both CloudTrail and Config event structures. **Replace the sample fake security-group ID with the real `$sg` if you intentionally invoke a test**, and use the Lambda **Test** feature only in your own authorized lab. Capture **Screenshot 6: event payload/parser demonstration**, if relevant.

## Step 16. Capture the architecture diagram for the blog

Illustrate the flow:

```text
EC2 security-group ingress change
     |                         AWS Config compliance check
     v                                   |
AWS CloudTrail event --------------------+
                 |                       |
                 +--> Amazon EventBridge+
                              |
                              v
                         AWS Lambda
                        /    |     \
               Inspect SG  Revoke   Tag SG
                              |
                              v
                    Amazon DynamoDB receipt

CloudTrail/Config delivery -> Amazon S3 telemetry bucket
Lambda execution logs     -> Amazon CloudWatch Logs
```

Suggested caption: **Dual-path event-driven AWS security-group remediation with selective rule removal and auditable outcomes.** This represents the architecture described in the PDF; it is not a latency benchmark.

## Step 17. Destroy every Terraform-managed lab resource

Do not leave this lab running after collecting your screenshots.

```powershell
terraform plan -destroy
terraform destroy
```

If you deployed with `enable_config_recorder=false`, **use the same setting for destroy**:

```powershell
terraform plan -destroy -var="enable_config_recorder=false"
terraform destroy -var="enable_config_recorder=false"
```

Review the resources, type `yes` to confirm, and wait until Terraform reports that destruction is complete. The project's `force_destroy=true` for the S3 bucket is only appropriate in a disposable lab. A pre-existing AWS Config recorder that was **not** created by Terraform will not be removed by this destroy.

Capture **Screenshot 7: Destroy complete**, then verify in the AWS console and your billing dashboard that no unexpected resources remain. Disable/delete any IAM access key created solely for this lab.

## Step 18. Upload documentation updates to GitHub

After adding your architecture diagram and **sanitized** screenshots to a publishable folder such as `docs/images/` (not the ignored `screenshots/` working folder), use:

```powershell
git status
git add .
git commit -m "Document deployment, verification, and cleanup"
git push
```

Do not upload sensitive Terraform state, AWS credential files, internal account details, or keys. You can publish the README and selected redacted screenshots. In the blog, link readers to your own successfully published GitHub repository.

## Quick troubleshooting

| Problem | What to check |
|---|---|
| `terraform` is not recognized | Put `terraform.exe` in a directory on Windows PATH and restart the terminal. |
| `aws` is not recognized | Reinstall AWS CLI v2 for Windows and restart the terminal. |
| `Unable to locate credentials` | Re-run `aws sso login --profile cb-speed-run` or configure the intended authorized profile; set `$env:AWS_PROFILE` again in this terminal. |
| `AccessDenied` | Your AWS identity lacks a specific action. Read the denied action and ask your lab account administrator to approve appropriate permissions. |
| No default VPC found | The sample needs a default VPC. Choose an authorized lab Region with a default VPC or update Terraform to accept another VPC ID. |
| Existing AWS Config recorder / quota error | Check `describe-configuration-recorders`; plan/apply/destroy consistently with `-var="enable_config_recorder=false"` if another customer-managed recorder exists. |
| `InvalidPermission.Duplicate` when injecting drift | A test ingress entry with the same protocol/port/CIDR is already present. Inspect the group before rerunning. |
| Security group still public after the test | Check the Lambda CloudWatch log group, EventBridge rule, AWS CloudTrail event delivery, Lambda IAM permissions and whether the event reached the function. Do not treat a short wait as proof of failure. |
| `git push` fails | Confirm your GitHub username/repo URL, GitHub browser authentication, and `git remote -v`. |
| Terraform wants to recreate the open rule | Do not re-apply during verification. `terraform plan` detects drift; use the intended `terraform destroy` when done. |

## Further reading and verification

- [GitHub: Adding locally hosted code to a repository](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github)
- [AWS CLI: Install on Windows](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [AWS CLI: Configure IAM Identity Center](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html)
- [AWS CLI: Authenticate with IAM access keys (when required)](https://docs.aws.amazon.com/cli/latest/userguide/cli-authentication-user.html)
- [AWS IAM: Manage access keys safely](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_access-keys.html)
- [HashiCorp: Install Terraform](https://developer.hashicorp.com/terraform/install)
- [HashiCorp: Terraform version-control recommendations](https://developer.hashicorp.com/terraform/language/style)
- [AWS Config: One customer-managed recorder per Region](https://docs.aws.amazon.com/config/latest/developerguide/stop-start-recorder.html)

**Closing line for the blog:** “The useful part of a self-healing security control isn't the alert. It's the controlled remediation: verify the live resource state, remove only the dangerous exposure, preserve legitimate access, record the action, and prove that everything can be safely torn down.”
