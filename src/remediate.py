"""Event-driven Security Group auto-remediation (disposable lab only)."""
import json
import os
import time
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

_ec2 = boto3.client("ec2")
_dynamodb = boto3.resource("dynamodb")
AUDIT_TABLE_NAME = os.environ["AUDIT_TABLE_NAME"]
PROTECTED_PORTS = {int(p) for p in os.environ.get("PROTECTED_PORTS", "22,3389").split(",")}
PUBLIC_CIDRS = {"0.0.0.0/0", "::/0"}
ALLOWED_SG_ID = os.environ.get("ALLOWED_SG_ID", "")


def extract_event_context(event):
    detail = event.get("detail") or {}
    if event.get("source") == "aws.ec2":
        group_id = (detail.get("requestParameters") or {}).get("groupId")
        actor = ((detail.get("userIdentity") or {}).get("arn") or "unknown-actor")
        return group_id, "CLOUDTRAIL_REALTIME", actor
    if event.get("source") == "aws.config":
        evaluation = detail.get("newEvaluationResult") or {}
        qualifier = ((evaluation.get("evaluationResultIdentifier") or {}).get("evaluationResultQualifier") or {})
        group_id = (detail.get("resourceId") or qualifier.get("resourceId") or
                    (detail.get("configurationItem") or {}).get("resourceId"))
        return group_id, "AWS_CONFIG", "config.amazonaws.com"
    return None, "UNSUPPORTED_SOURCE", "unknown"


def exposes_protected_port(from_port, to_port, protocol):
    # -1 means all protocols/ports, including SSH and RDP.
    if protocol == "-1":
        return True
    if protocol not in ("tcp", "6"):
        return False
    if from_port is None or to_port is None:
        return False
    return any(from_port <= port <= to_port for port in PROTECTED_PORTS)


def lambda_handler(event, context):
    start_time = time.time()
    group_id, trigger_source, actor = extract_event_context(event)
    if not group_id:
        result = {"status": "IGNORED", "reason": "No security group ID in event", "source": trigger_source}
        print(json.dumps(result))
        return result
    if group_id != ALLOWED_SG_ID:
        result = {"status": "IGNORED", "reason": "Not the protected demo security group", "group_id": group_id}
        print(json.dumps(result))
        return result

    response = _ec2.describe_security_groups(GroupIds=[group_id])
    group = response["SecurityGroups"][0]
    permissions_to_revoke = []
    for permission in group.get("IpPermissions", []):
        protocol = permission.get("IpProtocol", "-1")
        from_port = permission.get("FromPort")
        to_port = permission.get("ToPort")
        if not exposes_protected_port(from_port, to_port, protocol):
            continue
        public_ipv4 = [r for r in permission.get("IpRanges", []) if r.get("CidrIp") in PUBLIC_CIDRS]
        public_ipv6 = [r for r in permission.get("Ipv6Ranges", []) if r.get("CidrIpv6") in PUBLIC_CIDRS]
        if public_ipv4 or public_ipv6:
            entry = {"IpProtocol": protocol}
            if from_port is not None:
                entry["FromPort"] = from_port
            if to_port is not None:
                entry["ToPort"] = to_port
            if public_ipv4:
                entry["IpRanges"] = public_ipv4
            if public_ipv6:
                entry["Ipv6Ranges"] = public_ipv6
            permissions_to_revoke.append(entry)

    if not permissions_to_revoke:
        result = {"status": "IDEMPOTENT_SKIP", "group_id": group_id,
                  "reason": "No public SSH/RDP ingress rules to remove"}
        print(json.dumps(result))
        return result

    try:
        _ec2.revoke_security_group_ingress(GroupId=group_id, IpPermissions=permissions_to_revoke)
    except ClientError as err:
        if err.response.get("Error", {}).get("Code") == "InvalidPermission.NotFound":
            # Concurrent duplicate event: another invocation already removed the rule.
            return {"status": "IDEMPOTENT_SKIP", "group_id": group_id, "reason": "Already revoked"}
        raise

    now = datetime.now(timezone.utc).isoformat()
    audit_id = f"{group_id}#{datetime.now(timezone.utc).strftime('%Y%m%d%H%M')}"
    # SG has already been secured at this point; audit/tagging may fail separately.
    _ec2.create_tags(Resources=[group_id], Tags=[
        {"Key": "AutoRemediated", "Value": "true"},
        {"Key": "LastRemediatedAt", "Value": now},
        {"Key": "RemediationSource", "Value": trigger_source}
    ])
    ledger_status = "RECORDED"
    try:
        _dynamodb.Table(AUDIT_TABLE_NAME).put_item(
            Item={
                "AuditId": audit_id,
                "SecurityGroupId": group_id,
                "TriggerSource": trigger_source,
                "ViolatingActor": actor,
                "RevokedPermissions": json.dumps(permissions_to_revoke),
                "RemediatedAt": now,
                "ExpiresAt": int(time.time()) + 90 * 86400
            },
            ConditionExpression="attribute_not_exists(AuditId)"
        )
    except ClientError as err:
        if err.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            ledger_status = "DEDUPLICATED_EXISTING_RECEIPT"
        else:
            raise

    result = {
        "status": "REMEDIATED", "audit_id": audit_id, "group_id": group_id,
        "trigger_source": trigger_source, "violating_actor": actor,
        "revoked_permissions": permissions_to_revoke, "ledger_status": ledger_status,
        "latency_ms": round((time.time() - start_time) * 1000, 2)
    }
    print(json.dumps(result))
    return result
