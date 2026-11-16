# Smoke test for modules/lambdavault: `make smoke PROJECT=lambdavault` runs it against the deployed examples/lambdavault
# (a copy in .smoke/lambdavault whose source is this repo's modules/lambdavault; seal = ssm, the default).
# Checks the real deployment: the proxy URL answers for a fresh Vault; an init with more than one key share is
# refused; `vault operator init -key-shares=1 -key-threshold=1` stores the unseal key in SSM and leaves Vault
# unsealed; a secret is written and read back; after a forced cold start Vault has unsealed itself from SSM.
# Needs AWS credentials (AWS_PROFILE) and boto3: the SSM parameter is checked and, at the end, deleted (Terraform
# does not manage it).
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

import boto3

out = json.loads(subprocess.run(["terraform", "-chdir=.smoke/lambdavault", "output", "-json"],
                                check=True, capture_output=True, text=True).stdout)
url = out["vault_addr"]["value"].rstrip("/")
parameter = out["unseal_key_parameter"]["value"]
region = url.split(".lambda-url.")[1].split(".")[0]
ssm, lam = boto3.client("ssm", region_name=region), boto3.client("lambda", region_name=region)
token = None


def call(method, path, body=None):
    headers = {"content-type": "application/json", **({"x-vault-token": token} if token else {})}
    req = urllib.request.Request(url + path, method=method, data=json.dumps(body).encode() if body else None,
                                 headers=headers)
    for attempt in range(6):   # a cold start can take seconds; a busy Vault answers 429
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.status, json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            if e.code in (429, 502) and attempt < 5:
                time.sleep(2 + attempt)
                continue
            raw = e.read()
            try:
                return e.code, json.loads(raw)
            except ValueError:
                return e.code, {"raw": raw.decode(errors="replace")[:300]}


def check(name, ok, detail=""):
    print(f"{'ok  ' if ok else 'FAIL'} {name}{' — ' + str(detail) if detail and not ok else ''}")
    if not ok:
        sys.exit(1)


def health():
    return call("GET", "/v1/sys/health?uninitcode=200&sealedcode=200")


try:
    status, h = health()
    check("the proxy URL answers: a fresh, not initialized Vault", status == 200 and h.get("initialized") is False,
          f"HTTP {status} {h}")
    status, s = call("GET", "/v1/sys/seal-status")
    check("seal = ssm is Vault's Shamir seal", status == 200 and s.get("type") == "shamir", f"HTTP {status} {s}")

    status, r = call("PUT", "/v1/sys/init", {"secret_shares": 5, "secret_threshold": 3})
    check("init with 5 key shares is refused (one key goes to SSM)", status == 400, f"HTTP {status} {r}")

    status, init = call("PUT", "/v1/sys/init", {"secret_shares": 1, "secret_threshold": 1})
    check("init -key-shares=1 -key-threshold=1", status == 200 and init.get("root_token") and not init.get("warnings"),
          f"HTTP {status} {init.get('warnings') or init.get('errors')}")
    token = init["root_token"]

    stored = ssm.get_parameter(Name=parameter, WithDecryption=True)["Parameter"]
    check("the unseal key is a SecureString in SSM", stored["Type"] == "SecureString" and stored["Value"] == init["keys"][0])

    status, h = health()
    check("unsealed right after init", status == 200 and h.get("initialized") and h.get("sealed") is False, h)

    status, r = call("POST", "/v1/sys/mounts/kv", {"type": "kv", "options": {"version": "2"}})
    check("enable kv-v2", status == 204, f"HTTP {status} {r}")
    status, r = call("POST", "/v1/kv/data/smoke", {"data": {"password": "p"}})
    check("write a secret", status == 200, f"HTTP {status} {r}")

    # a configuration change makes Lambda start new instances: the next call is a cold start, sealed until the
    # entrypoint has read the key from SSM
    function = out["function_name"]["value"]
    lam.update_function_configuration(FunctionName=function, Description=f"smoke {time.time():.0f}")
    lam.get_waiter("function_updated_v2").wait(FunctionName=function)
    status, h = health()
    check("after a cold start: unsealed from SSM", status == 200 and h.get("sealed") is False, f"HTTP {status} {h}")
    status, r = call("GET", "/v1/kv/data/smoke")
    check("the secret survives the cold start (S3)", status == 200 and r["data"]["data"] == {"password": "p"},
          f"HTTP {status} {r}")
finally:
    try:
        ssm.delete_parameter(Name=parameter)   # not Terraform's: written by the proxy at init
    except ssm.exceptions.ParameterNotFound:
        pass

print("smoke lambdavault: ok")
