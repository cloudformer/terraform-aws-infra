# Smoke test for modules/lambdachecks: `make smoke PROJECT=lambdachecks` runs it against the deployed
# examples/lambdachecks (a copy in .smoke/lambdachecks whose source is this repo's modules/lambdachecks).
# TF_VAR_console_password and TF_VAR_secret_key: set by the Makefile.
# Checks the real deployment answers: Healthchecks loads (Django, its static files) and shows the setup page of a
# fresh deployment, the setup key is checked, s3rds refuses a request without sign-in and answers with it, and the
# whole chain works — the setup page starts migrate in the manage function (the web role may invoke it), which
# creates Healthchecks' database in s3rds over HTTPS (DB_HOST + the shared credentials).
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

out = json.loads(subprocess.run(["terraform", "-chdir=.smoke/lambdachecks", "output", "-json"],
                                check=True, capture_output=True, text=True).stdout)
url = out["url"]["value"].rstrip("/")
db_url = out["db_url"]["value"].rstrip("/")
auth = "Basic " + base64.b64encode(f"admin:{os.environ['TF_VAR_console_password']}".encode()).decode()


def call(method, full_url, form=None, headers=None):
    req = urllib.request.Request(full_url, method=method, headers=headers or {},
                                 data=urllib.parse.urlencode(form).encode() if form is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def check(name, ok, detail=""):
    print(f"{'ok  ' if ok else 'FAIL'} {name}{' — ' + detail if detail and not ok else ''}")
    if not ok:
        sys.exit(1)


status, body = call("GET", url + "/")
check("Healthchecks answers: the setup page of a fresh deployment", status == 200 and b"lambdachecks setup" in body,
      f"HTTP {status} {body[:300]!r}")

status, body = call("POST", url + "/setup/migrate", {"key": "not-the-setup-key"})
check("a wrong setup key is refused", status == 200 and b"Wrong setup key" in body, f"HTTP {status}")

status, _ = call("GET", db_url + "/api/databases")
check("s3rds refuses without sign-in", status == 401, f"HTTP {status}")

status, body = call("GET", db_url + "/api/databases", headers={"authorization": auth})
check("s3rds answers with sign-in", status == 200, f"HTTP {status} {body[:300]!r}")

status, body = call("POST", url + "/setup/migrate", {"key": os.environ["TF_VAR_secret_key"]})
check("the setup key starts migrate", status == 200 and b"Migrations started" in body, f"HTTP {status} {body[:300]!r}")

# the manage function creates the database first, then migrates (minutes); the database appearing is enough
deadline, found = time.time() + 180, False
while time.time() < deadline and not found:
    time.sleep(10)
    status, body = call("GET", db_url + "/api/databases", headers={"authorization": auth})
    found = status == 200 and b"healthchecks" in body
check("manage function created Healthchecks' database in s3rds", found, f"HTTP {status} {body[:300]!r}")

print("smoke lambdachecks: ok")
