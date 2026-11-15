# Smoke test for modules/s3keepass: `make smoke PROJECT=s3keepass` runs it against the deployed examples/s3keepass
# (a copy in .smoke/s3keepass whose source is this repo's modules/s3keepass). TF_VAR_console_password: set by the Makefile.
# Checks the real deployment answers: the web UI, sign-in, the vault list, the new-vault template, and a vault file
# saved, listed, read back and deleted (bytes only: the KDBX crypto runs in the browser and is tested in s3keepass).
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request

out = json.loads(subprocess.run(["terraform", "-chdir=.smoke/s3keepass", "output", "-json"],
                                check=True, capture_output=True, text=True).stdout)
url = out["console_url"]["value"].rstrip("/")
auth = "Basic " + base64.b64encode(f"admin:{os.environ['TF_VAR_console_password']}".encode()).decode()


def call(method, path, body=None, headers=None, signed=True):
    req = urllib.request.Request(url + path, data=body, method=method,
                                 headers=dict({"authorization": auth} if signed else {}, **(headers or {})))
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read(), r.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers


def check(name, ok, detail=""):
    print(f"{'ok  ' if ok else 'FAIL'} {name}{' — ' + detail if detail and not ok else ''}")
    if not ok:
        sys.exit(1)


status, body, _ = call("GET", "/", signed=False)
check("web UI at GET /", status == 200 and b"s3keepass" in body, f"HTTP {status}")

status, _, _ = call("GET", "/api/tree", signed=False)
check("API refuses without sign-in", status == 401, f"HTTP {status}")

status, body, _ = call("GET", "/api/tree")
check("vault list with sign-in", status == 200 and "folders" in json.loads(body), f"HTTP {status} {body[:200]!r}")

status, body, _ = call("GET", "/api/template")
t = json.loads(body) if status == 200 else {}
check("new-vault template (base + custom)", status == 200 and t.get("template", {}).get("kdf", {}).get("memory_mib") == 128,
      f"HTTP {status} {body[:200]!r}")

data = b"\x03\xd9\xa2\x9a\x67\xfb\x4b\xb5" + os.urandom(64)   # a KDBX signature + bytes: the server stores bytes as given
status, body, h = call("PUT", "/api/vaults/smoke", data, {"if-none-match": "*", "content-type": "application/octet-stream"})
check("save a new vault file", status in (200, 201), f"HTTP {status} {body[:200]!r}")
etag = h.get("etag") or json.loads(body).get("etag")

status, body, _ = call("GET", "/api/vaults/smoke")
check("read it back", status == 200 and body == data, f"HTTP {status}")

status, body, _ = call("DELETE", "/api/vaults/smoke", headers={"if-match": etag})
check("delete it", status in (200, 204), f"HTTP {status} {body[:200]!r}")

print("smoke s3keepass: ok")
