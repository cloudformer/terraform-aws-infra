# Smoke test for modules/lambdaflow: `make smoke PROJECT=lambdaflow` runs it against the deployed examples/lambdaflow
# (a copy in .smoke/lambdaflow whose source is this repo's modules/lambdaflow). TF_VAR_console_password: set by the Makefile.
# Checks the real deployment works end to end: the console, sign-in, a DAG file uploaded and parsed by the worker,
# a run triggered through Step Functions, both tasks run by the worker (with the layer loaded), the DAG deleted.
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

out = json.loads(subprocess.run(["terraform", "-chdir=.smoke/lambdaflow", "output", "-json"],
                                check=True, capture_output=True, text=True).stdout)
url = out["console_url"]["value"].rstrip("/")
auth = "Basic " + base64.b64encode(f"admin:{os.environ['TF_VAR_console_password']}".encode()).decode()

DAG = '''
from datetime import datetime
from airflow.sdk import DAG
from airflow.providers.standard.operators.python import PythonOperator

def hello():
    return "hello"

with DAG("smoke", start_date=datetime(2026, 1, 1), schedule=None) as dag:
    a = PythonOperator(task_id="a", python_callable=hello)
    b = PythonOperator(task_id="b", python_callable=hello)
    a >> b
'''


def call(method, path, body=None, signed=True):
    req = urllib.request.Request(url + path, method=method, data=json.dumps(body).encode() if body is not None else None,
                                 headers=dict({"authorization": auth} if signed else {}, **{"content-type": "application/json"}))
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def check(name, ok, detail=""):
    print(f"{'ok  ' if ok else 'FAIL'} {name}{' — ' + detail if detail and not ok else ''}")
    if not ok:
        sys.exit(1)


status, body = call("GET", "/", signed=False)
check("console at GET /", status == 200 and b"lambdaflow" in body, f"HTTP {status}")

status, _ = call("GET", "/api/dags", signed=False)
check("API refuses without sign-in", status == 401, f"HTTP {status}")

status, body = call("PUT", "/api/files/smoke.py", {"source": DAG})
check("DAG file uploaded and parsed by the worker", status in (200, 201), f"HTTP {status} {body[:300]!r}")

status, body = call("POST", "/api/dags/smoke/runs", {"conf": {}, "unpause": True})
check("run triggered (Step Functions)", status in (200, 201), f"HTTP {status} {body[:300]!r}")
run_id = json.loads(body)["run_id"]

state, end = None, time.time() + 300
while time.time() < end:
    status, body = call("GET", f"/api/dags/smoke/runs/{run_id}")
    state = json.loads(body)["run"]["state"] if status == 200 else None
    if state in ("success", "failed"):
        break
    time.sleep(5)
check("run succeeded: both tasks ran on the worker", state == "success", f"state {state}")

status, body = call("DELETE", "/api/dags/smoke")
check("DAG deleted", status in (200, 204), f"HTTP {status} {body[:300]!r}")

print("smoke lambdaflow: ok")
