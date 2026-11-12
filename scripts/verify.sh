#!/usr/bin/env bash
set -euo pipefail
SG_ID=$(terraform output -raw target_security_group_id)
TABLE_NAME=$(terraform output -raw dynamodb_audit_table)
LAMBDA_NAME=$(terraform output -raw lambda_function_name)
echo "1. INITIAL STATE - demo SG: $SG_ID"
aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissions' --output table

echo "2. INJECTING DRIFT into an unattached disposable SG"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --ip-permissions \
  'IpProtocol=tcp,FromPort=22,ToPort=22,IpRanges=[{CidrIp=0.0.0.0/0,Description="Lab Public SSH"}]' \
  'IpProtocol=tcp,FromPort=3389,ToPort=3389,IpRanges=[{CidrIp=0.0.0.0/0,Description="Lab Public RDP"}]'

echo "3. Waiting briefly for EventBridge -> Lambda (eventual delivery, not guaranteed within 5s)"
sleep 15
aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].{IngressRules:IpPermissions,Tags:Tags}' --output json

echo "4. AUDIT RECEIPTS"
aws dynamodb scan --table-name "$TABLE_NAME" --output json

echo "5. Lambda log group: /aws/lambda/$LAMBDA_NAME"
echo "If public rules remain, inspect CloudWatch logs and retry after event propagation."
