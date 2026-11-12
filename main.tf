terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_vpc" "default" { default = true }
resource "random_id" "suffix" { byte_length = 3 }
locals { name_prefix = "${var.project_name}-${random_id.suffix.hex}" }

# 1. Conditional-write audit receipts, with 90-day TTL
resource "aws_dynamodb_table" "audit_ledger" {
  name         = "${local.name_prefix}-audit-ledger"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "AuditId"
  attribute {
    name = "AuditId"
    type = "S"
  }
  ttl {
    attribute_name = "ExpiresAt"
    enabled        = true
  }
  tags = { Project = var.project_name, ManagedBy = "Terraform" }
}

# 2. Unattached, disposable test SG only. Never attach to real instances.
resource "aws_security_group" "test_sg" {
  name        = "${local.name_prefix}-target-sg"
  description = "Unattached lab SG for event-driven remediation"
  vpc_id      = data.aws_vpc.default.id
  ingress {
    description = "Legitimate corporate SSH rule - preserve"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.20.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${local.name_prefix}-target-sg" }
}

# 3. CloudTrail management-event delivery to S3
resource "aws_s3_bucket" "security_telemetry" {
  bucket        = "${local.name_prefix}-telemetry-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # LAB ONLY: removes demo objects during destroy
}
resource "aws_s3_bucket_public_access_block" "telemetry" {
  bucket                  = aws_s3_bucket.security_telemetry.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_server_side_encryption_configuration" "telemetry_sse" {
  bucket = aws_s3_bucket.security_telemetry.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "telemetry_policy" {
  bucket = aws_s3_bucket.security_telemetry.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAndConfigAclCheck"
        Effect    = "Allow"
        Principal = { Service = ["cloudtrail.amazonaws.com", "config.amazonaws.com"] }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.security_telemetry.arn
      },
      {
        Sid       = "AWSCloudTrailAndConfigWrite"
        Effect    = "Allow"
        Principal = { Service = ["cloudtrail.amazonaws.com", "config.amazonaws.com"] }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.security_telemetry.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" } }
      }
    ]
  })
}
resource "aws_cloudtrail" "management_trail" {
  name                          = "${local.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.security_telemetry.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_logging                = true
  depends_on                    = [aws_s3_bucket_policy.telemetry_policy]
}

# 4. AWS Config: new recorder only if account does not have one.
resource "aws_iam_role" "config_role" {
  count = var.enable_config_recorder ? 1 : 0
  name  = "${local.name_prefix}-config-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "config.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy_attachment" "config_policy_attach" {
  count      = var.enable_config_recorder ? 1 : 0
  role       = aws_iam_role.config_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}
resource "aws_config_configuration_recorder" "main" {
  count    = var.enable_config_recorder ? 1 : 0
  name     = "${local.name_prefix}-recorder"
  role_arn = aws_iam_role.config_role[0].arn
  recording_group {
    all_supported                 = false
    include_global_resource_types = false
    resource_types                = ["AWS::EC2::SecurityGroup"]
  }
  depends_on = [aws_iam_role_policy_attachment.config_policy_attach]
}
resource "aws_config_delivery_channel" "main" {
  count          = var.enable_config_recorder ? 1 : 0
  name           = "${local.name_prefix}-channel"
  s3_bucket_name = aws_s3_bucket.security_telemetry.bucket
  depends_on     = [aws_config_configuration_recorder.main, aws_s3_bucket_policy.telemetry_policy]
}
resource "aws_config_configuration_recorder_status" "main" {
  count      = var.enable_config_recorder ? 1 : 0
  name       = aws_config_configuration_recorder.main[0].name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.main]
}
resource "aws_config_config_rule" "restricted_ssh" {
  name = "${local.name_prefix}-incoming-ssh-disabled"
  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
  scope { compliance_resource_types = ["AWS::EC2::SecurityGroup"] }
  depends_on = [aws_config_configuration_recorder_status.main]
}

# 5. EventBridge-triggered Lambda with narrowly scoped data/actions

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/remediate.py"
  output_path = "${path.module}/src/remediate.zip"
}
resource "aws_iam_role" "remediation_lambda_role" {
  name = "${local.name_prefix}-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "lambda.amazonaws.com" } }]
  })
}
resource "aws_iam_role_policy" "remediation_least_privilege" {
  name = "${local.name_prefix}-remediate-policy"
  role = aws_iam_role.remediation_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DescribeSecurityGroups"
        Effect   = "Allow"
        Action   = ["ec2:DescribeSecurityGroups"]
        Resource = "*" # AWS Describe API requires Resource *
      },
      {
        Sid      = "FixOnlyDemoSecurityGroup"
        Effect   = "Allow"
        Action   = ["ec2:RevokeSecurityGroupIngress", "ec2:CreateTags"]
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:security-group/${aws_security_group.test_sg.id}"
      },
      {
        Sid      = "DynamoDBAuditWrite"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem"]
        Resource = aws_dynamodb_table.audit_ledger.arn
      },
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
      }
    ]
  })
}
resource "aws_lambda_function" "remediator" {
  function_name    = "${local.name_prefix}-engine"
  role             = aws_iam_role.remediation_lambda_role.arn
  handler          = "remediate.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  memory_size      = 128
  timeout          = 5
  environment {
    variables = {
      AUDIT_TABLE_NAME = aws_dynamodb_table.audit_ledger.name
      PROTECTED_PORTS  = "22,3389"
      # Restrict Lambda to the unattached demo SG; safeguards other SGs.
      ALLOWED_SG_ID    = aws_security_group.test_sg.id
    }
  }
  depends_on = [aws_iam_role_policy.remediation_least_privilege]
}
resource "aws_cloudwatch_event_rule" "security_group_drift" {
  name        = "${local.name_prefix}-sg-drift-rule"
  description = "AuthorizeSecurityGroupIngress API and AWS Config compliance changes"
  event_pattern = jsonencode({
    "$or" = [
      {
        source        = ["aws.ec2"]
        "detail-type" = ["AWS API Call via CloudTrail"]
        detail = {
          eventSource = ["ec2.amazonaws.com"]
          eventName   = ["AuthorizeSecurityGroupIngress"]
        }
      },
      {
        source        = ["aws.config"]
        "detail-type" = ["Config Rules Compliance Change"]
        detail = {
          configRuleName = [aws_config_config_rule.restricted_ssh.name]
          newEvaluationResult = { complianceType = ["NON_COMPLIANT"] }
        }
      }
    ]
  })
}
resource "aws_cloudwatch_event_target" "invoke_remediator" {
  rule      = aws_cloudwatch_event_rule.security_group_drift.name
  target_id = "InvokeRemediationLambda"
  arn       = aws_lambda_function.remediator.arn
}
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediator.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.security_group_drift.arn
}
