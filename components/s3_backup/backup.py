# One snapshot: every object under PREFIXES in SOURCE_BUCKET is copied to BACKUP_BUCKET/<UTC time>/<key>.
# Run by the schedule; old snapshots are expired by the backup bucket's lifecycle rule.
# Restore one:  aws s3 sync s3://<backup bucket>/<snapshot>/ s3://<source bucket>/
import json
import os
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")


def handler(event, context):
    source, backup = os.environ["SOURCE_BUCKET"], os.environ["BACKUP_BUCKET"]
    snapshot = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%MZ")  # sorts by time, whatever the frequency
    copied = 0
    for prefix in json.loads(os.environ["PREFIXES"]):
        for page in s3.get_paginator("list_objects_v2").paginate(Bucket=source, Prefix=prefix):
            for obj in page.get("Contents", []):
                # managed copy: multipart above 8 MB, so a large database file copies as well
                s3.copy({"Bucket": source, "Key": obj["Key"]}, backup, f"{snapshot}/{obj['Key']}")
                copied += 1
    result = {"snapshot": snapshot, "objects": copied}
    print(json.dumps(result))
    return result
