"""Stage lambdazap from a released lambdazap on PyPI: the Lambda's code and the scan image's build context.

    python3 build.py "lambdazap==0.1.0" <out dir>

    <out dir>/code   lambdazap itself (--no-deps: it has none; boto3 comes with the Lambda runtime)
                     code/lambdazap/server   lambda_function.py, index.html: the web UI + API Lambda
                     code/lambdazap/image    Dockerfile, ...: the Docker build context of the scan image (ZAP)

Terraform runs it at plan time (main.tf). Prints {"code": ..., "image": ..., "tag": ...} for Terraform's external
data source; tag is the content hash of the image directory, the image tag: the image is rebuilt only when what
it is built from changes.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys


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
    image = os.path.join(code, "lambdazap", "image")
    stamp = out + ".stamp"
    # same spec as last time -> reuse the directory as it is (a reinstall gives new file times, so a new zip
    # hash and a Lambda update on every plan)
    if not (os.path.isdir(out) and os.path.isfile(stamp) and open(stamp, encoding="utf-8").read() == spec):
        shutil.rmtree(out, ignore_errors=True)
        # no .pyc: they embed timestamps, the zip hash would change every plan
        r = subprocess.run([sys.executable, "-m", "pip", "-q", "--disable-pip-version-check", "install",
                            "--target", code, "--no-compile", "--no-deps", spec], capture_output=True, text=True)
        if r.returncode:
            sys.exit(f"build.py: pip failed: {r.stderr.strip()[-500:]}")
        shutil.rmtree(os.path.join(code, "bin"), ignore_errors=True)
        if not os.path.isfile(os.path.join(image, "Dockerfile")):
            sys.exit(f"build.py: {spec} has no lambdazap/image/Dockerfile")
        with open(stamp, "w", encoding="utf-8") as fh:
            fh.write(spec)
    print(json.dumps({"code": code, "image": image, "tag": content_hash(image)}))


if __name__ == "__main__":
    main()
