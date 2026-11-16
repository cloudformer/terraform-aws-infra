"""Stage lambdavault for Lambda from a released lambdavault on PyPI: the Vault image's build context and the proxy.

    python3 build.py "lambdavault==0.1.2" <out dir>

    <out dir>/code   lambdavault itself (--no-deps: it has none)
                     code/lambdavault/server   Dockerfile, vault.hcl, ...: the Docker build context of the Vault image
                     code/lambdavault/proxy    lambda_function.py: the proxy Lambda's zip

Terraform runs it at plan time (main.tf). Prints {"server": ..., "proxy": ..., "tag": ...} for Terraform's external
data source; tag is the content hash of the server directory, the image tag: the image is rebuilt only when what
it is built from changes.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys


def pip(*args):
    # no .pyc: they embed timestamps
    r = subprocess.run([sys.executable, "-m", "pip", "-q", "--disable-pip-version-check", "install", "--no-compile",
                        *args], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"build.py: pip failed: {r.stderr.strip()[-500:]}")


def content_hash(top):
    h = hashlib.sha256()
    for root, dirs, files in os.walk(top):
        dirs[:] = sorted(d for d in dirs if d != "__pycache__")
        for name in sorted(files):
            path = os.path.join(root, name)
            h.update(os.path.relpath(path, top).encode() + b"\0")
            with open(path, "rb") as fh:
                h.update(hashlib.sha256(fh.read()).digest())
    return h.hexdigest()[:16]


def main():
    spec, out = sys.argv[1], os.path.abspath(sys.argv[2])
    code = os.path.join(out, "code")
    server, proxy = os.path.join(code, "lambdavault", "server"), os.path.join(code, "lambdavault", "proxy")
    stamp = out + ".stamp"
    # same spec as last time -> reuse the directory as it is (nothing is downloaded on every plan)
    if not (os.path.isdir(out) and os.path.isfile(stamp) and open(stamp, encoding="utf-8").read() == spec):
        shutil.rmtree(out, ignore_errors=True)
        pip("--target", code, "--no-deps", spec)
        shutil.rmtree(os.path.join(code, "bin"), ignore_errors=True)
        if not os.path.isfile(os.path.join(server, "Dockerfile")):
            sys.exit(f"build.py: {spec} has no lambdavault/server/Dockerfile (lambdavault 0.1.1 or later is needed)")
        with open(stamp, "w", encoding="utf-8") as fh:
            fh.write(spec)
    print(json.dumps({"server": server, "proxy": proxy, "tag": content_hash(server)}))


if __name__ == "__main__":
    main()
