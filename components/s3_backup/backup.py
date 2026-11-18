# Snapshots of PREFIXES in SOURCE_BUCKET into BACKUP_BUCKET/<UTC time>/<key>, taken only when needed.
# Each run (the schedule) compares the source with the newest snapshot's manifest.json and takes a new snapshot when
#   there is none yet, the keys or their ETags differ, or the newest is FORCE_AFTER_HOURS old (so a fresh one exists
#   before the lifecycle rule expires it); otherwise it does nothing.
# A snapshot is a full copy; manifest.json (time + each key's source ETag) is written last, so a folder without one is
# a run that did not finish and is ignored. Old snapshots are expired by the backup bucket's lifecycle rule.
# Restore one:  aws s3 sync s3://<backup bucket>/<snapshot>/ s3://<source bucket>/ --exclude "manifest.json"
import json
import os
from datetime import datetime, timedelta, timezone

import boto3

s3 = boto3.client("s3")

MANIFEST = "manifest.json"
SLACK = timedelta(minutes=10)  # the schedule fires at about the same minute each time; don't miss the due run by seconds


def now():
    return datetime.now(timezone.utc)


def source_objects(source, prefixes):
    objects = {}
    for prefix in prefixes:
        for page in s3.get_paginator("list_objects_v2").paginate(Bucket=source, Prefix=prefix):
            for obj in page.get("Contents", []):
                objects[obj["Key"]] = obj["ETag"]
    return objects


def newest_snapshot(backup):
    """(folder, manifest) of the newest snapshot that has a manifest.json, or (None, None)."""
    folders = []
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=backup, Delimiter="/"):
        folders += [p["Prefix"].rstrip("/") for p in page.get("CommonPrefixes", [])]
    for folder in sorted(folders, reverse=True):  # <UTC time> names sort by time
        try:
            body = s3.get_object(Bucket=backup, Key=f"{folder}/{MANIFEST}")["Body"].read()
        except s3.exceptions.NoSuchKey:
            continue
        return folder, json.loads(body)
    return None, None


def handler(event, context):
    source, backup = os.environ["SOURCE_BUCKET"], os.environ["BACKUP_BUCKET"]
    force_after = timedelta(hours=float(os.environ["FORCE_AFTER_HOURS"]))
    started = now()

    objects = source_objects(source, json.loads(os.environ["PREFIXES"]))
    latest, manifest = newest_snapshot(backup)
    if manifest is None:
        reason = "first"
    elif manifest["objects"] != objects:
        reason = "changed"
    elif started - datetime.fromisoformat(manifest["time"]) >= force_after - SLACK:
        reason = "forced"
    else:
        result = {"snapshot": latest, "taken": False, "reason": "unchanged", "objects": len(objects)}
        print(json.dumps(result))
        return result

    snapshot = started.strftime("%Y-%m-%dT%H%M%SZ")  # sorts by time; to the second, so a rerun never writes into a snapshot
    for key in objects:
        # managed copy: multipart above 8 MB, so a large database file copies as well
        s3.copy({"Bucket": source, "Key": key}, backup, f"{snapshot}/{key}")
    s3.put_object(Bucket=backup, Key=f"{snapshot}/{MANIFEST}", ContentType="application/json",
                  Body=json.dumps({"time": started.isoformat(), "objects": objects}, indent=1).encode())
    result = {"snapshot": snapshot, "taken": True, "reason": reason, "objects": len(objects)}
    print(json.dumps(result))
    return result
