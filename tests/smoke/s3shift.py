# Smoke test for modules/s3shift: `make smoke PROJECT=s3shift` runs it against the deployed examples/s3shift
# (a copy in .smoke/s3shift whose source is this repo's modules/s3shift). TF_VAR_console_password: set by the Makefile.
# Checks the real deployment answers: the console, sign-in, and SQL through DuckDB with the layer loaded —
# a managed table created, written to S3 as Parquet, read back and dropped.
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

out = json.loads(subprocess.run(["terraform", "-chdir=.smoke/s3shift", "output", "-json"],
                                check=True, capture_output=True, text=True).stdout)
url = out["console_url"]["value"].rstrip("/")
auth = "Basic " + base64.b64encode(f"admin:{os.environ['TF_VAR_console_password']}".encode()).decode()


def call(method, path, body=None, signed=True):
    req = urllib.request.Request(url + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers=dict({"authorization": auth} if signed else {}, **{"content-type": "application/json"}))
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def check(name, ok, detail=""):
    print(f"{'ok  ' if ok else 'FAIL'} {name}{' — ' + detail if detail and not ok else ''}")
    if not ok:
        sys.exit(1)


def sql(text):
    status, body = call("POST", "/api/query", {"sql": text})
    check(text, status == 200, f"HTTP {status} {body[:300]!r}")
    return json.loads(body)


status, body = call("GET", "/", signed=False)
check("console at GET /", status == 200 and b"s3shift" in body, f"HTTP {status}")

status, _ = call("POST", "/api/query", {"sql": "SELECT 1"}, signed=False)
check("API refuses without sign-in", status == 401, f"HTTP {status}")

check("DuckDB answers", sql("SELECT 1 + 1 AS two")["rows"] == [[2]])
sql("CREATE TABLE smoke (id INT, name VARCHAR(20))")
sql("INSERT INTO smoke VALUES (1, 'a'), (2, 'b')")
check("managed table read back from S3", sql("SELECT count(*) FROM smoke")["rows"] == [[2]])
sql("DROP TABLE smoke")

print("smoke s3shift: ok")
