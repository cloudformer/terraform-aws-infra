#!/usr/bin/env bash
# ztna jump agent: self-terminate when the lease runs out, or after IDLE_MINUTES with no SSM session.
# The launch template's user-data writes /etc/ztna.env (BUCKET, IDLE_MINUTES, REGION) and runs this as a service.
# The instance's IAM role needs: s3:GetObject on the lease, ec2:TerminateInstances on itself.
set -u
# shellcheck disable=SC1091
source /etc/ztna.env   # BUCKET, IDLE_MINUTES, REGION

imds_token() { curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300"; }
imds() { curl -s -H "X-aws-ec2-metadata-token: $(imds_token)" \
  "http://169.254.169.254/latest/meta-data/$1"; }

IID="$(imds instance-id)"
idle=0

terminate() { aws ec2 terminate-instances --instance-ids "$IID" --region "$REGION" >/dev/null 2>&1; exit 0; }

while true; do
  # 1) hard stop at the lease's "until" (lexical compare works on same-format UTC ISO)
  until="$(aws s3 cp "s3://$BUCKET/leases/$IID.json" - --region "$REGION" 2>/dev/null \
    | python3 -c 'import sys,json; print(json.load(sys.stdin).get("until",""))' 2>/dev/null)"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [ -n "$until" ] && [[ "$now" > "$until" ]]; then terminate; fi

  # 2) idle: a live SSM session (shell or port-forward) runs an ssm-session-worker; none = idle
  if pgrep -f 'ssm-session-worker|sessionworker' >/dev/null 2>&1; then idle=0; else idle=$((idle + 1)); fi
  if [ "$idle" -ge "${IDLE_MINUTES:-30}" ]; then terminate; fi

  sleep 60
done
