# components/s3_backup/backup.py against a fake S3 (moto): a snapshot only when needed. No AWS.
#   python3 -m pytest tests/unit -q        (needs boto3, moto, pytest)
import json
import os
import sys
from datetime import datetime, timedelta, timezone

import boto3
import pytest
from moto import mock_aws

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "components", "s3_backup"))
os.environ.update(AWS_DEFAULT_REGION="us-east-1", AWS_ACCESS_KEY_ID="test", AWS_SECRET_ACCESS_KEY="test")
import backup  # noqa: E402

SOURCE, BACKUP = "src", "src-backup"
T0 = datetime(2026, 11, 1, 3, 0, tzinfo=timezone.utc)


@pytest.fixture
def s3(monkeypatch):
    with mock_aws():
        client = boto3.client("s3")
        client.create_bucket(Bucket=SOURCE)
        client.create_bucket(Bucket=BACKUP)
        client.put_object(Bucket=SOURCE, Key="keepass/a.kdbx", Body=b"a1")
        client.put_object(Bucket=SOURCE, Key="keepass/b.kdbx", Body=b"b1")
        client.put_object(Bucket=SOURCE, Key="log/x", Body=b"not backed up")
        monkeypatch.setattr(backup, "s3", client)
        monkeypatch.setenv("SOURCE_BUCKET", SOURCE)
        monkeypatch.setenv("BACKUP_BUCKET", BACKUP)
        monkeypatch.setenv("PREFIXES", json.dumps(["keepass/"]))
        monkeypatch.setenv("FORCE_AFTER_HOURS", str(15 * 24))  # keep_days 30
        yield client


def run_at(monkeypatch, at):
    monkeypatch.setattr(backup, "now", lambda: at)
    return backup.handler({}, None)


def keys(s3, folder):
    return sorted(o["Key"] for o in s3.list_objects_v2(Bucket=BACKUP, Prefix=folder + "/").get("Contents", []))


def test_first_run_takes_a_full_snapshot(s3, monkeypatch):
    s3.put_object(Bucket=BACKUP, Key="2026-10-31T030000Z/keepass/a.kdbx", Body=b"half done")  # no manifest: ignored
    r = run_at(monkeypatch, T0)
    assert r == {"snapshot": "2026-11-01T030000Z", "taken": True, "reason": "first", "objects": 2}
    assert keys(s3, r["snapshot"]) == ["2026-11-01T030000Z/keepass/a.kdbx", "2026-11-01T030000Z/keepass/b.kdbx",
                                       "2026-11-01T030000Z/manifest.json"]
    manifest = json.loads(s3.get_object(Bucket=BACKUP, Key="2026-11-01T030000Z/manifest.json")["Body"].read())
    etags = {o["Key"]: o["ETag"] for o in s3.list_objects_v2(Bucket=SOURCE, Prefix="keepass/")["Contents"]}
    assert manifest == {"time": T0.isoformat(), "objects": etags}


def test_unchanged_does_nothing(s3, monkeypatch):
    run_at(monkeypatch, T0)
    r = run_at(monkeypatch, T0 + timedelta(days=1))
    assert r == {"snapshot": "2026-11-01T030000Z", "taken": False, "reason": "unchanged", "objects": 2}
    folders = s3.list_objects_v2(Bucket=BACKUP, Delimiter="/")["CommonPrefixes"]
    assert [p["Prefix"] for p in folders] == ["2026-11-01T030000Z/"]


def test_changed_takes_a_new_snapshot(s3, monkeypatch):
    run_at(monkeypatch, T0)
    s3.put_object(Bucket=SOURCE, Key="keepass/a.kdbx", Body=b"a2")
    r = run_at(monkeypatch, T0 + timedelta(hours=1))
    assert r == {"snapshot": "2026-11-01T040000Z", "taken": True, "reason": "changed", "objects": 2}
    assert s3.get_object(Bucket=BACKUP, Key="2026-11-01T040000Z/keepass/a.kdbx")["Body"].read() == b"a2"
    assert s3.get_object(Bucket=BACKUP, Key="2026-11-01T030000Z/keepass/a.kdbx")["Body"].read() == b"a1"


def test_unchanged_but_due_is_forced(s3, monkeypatch):
    run_at(monkeypatch, T0)
    assert run_at(monkeypatch, T0 + timedelta(days=14))["taken"] is False
    r = run_at(monkeypatch, T0 + timedelta(days=15))
    assert r == {"snapshot": "2026-11-16T030000Z", "taken": True, "reason": "forced", "objects": 2}
    assert keys(s3, r["snapshot"])[-1] == "2026-11-16T030000Z/manifest.json"
