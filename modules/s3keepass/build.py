"""Stage the s3keepass server for Lambda: a released s3keepass from PyPI (pure Python, no dependencies).

    python3 build.py "s3keepass==0.1.2" <out dir>

Terraform runs it at plan time (main.tf). Prints {"dir": "<out dir>"} for Terraform's external data source.
"""
import json
import os
import shutil
import subprocess
import sys

# pure Python with no dependencies (boto3 comes with the Lambda runtime): the same files for arm64 and x86_64
PLATFORM = ["--no-deps"]


def main():
    spec, out = sys.argv[1], os.path.abspath(sys.argv[2])
    stamp = out + ".stamp"
    # same spec as last time -> reuse the directory as it is (a reinstall gives new file times, so a new zip
    # hash and a Lambda update on every plan)
    if os.path.isdir(out) and os.path.isfile(stamp) and open(stamp, encoding="utf-8").read() == spec:
        print(json.dumps({"dir": out}))
        return
    shutil.rmtree(out, ignore_errors=True)
    # no .pyc: they embed timestamps, the zip hash would change every plan
    r = subprocess.run([sys.executable, "-m", "pip", "-q", "--disable-pip-version-check", "install",
                        "--target", out, "--no-compile", *PLATFORM, spec], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"build.py: pip failed: {r.stderr.strip()[-500:]}")
    shutil.rmtree(os.path.join(out, "bin"), ignore_errors=True)
    with open(stamp, "w", encoding="utf-8") as fh:
        fh.write(spec)
    print(json.dumps({"dir": out}))


if __name__ == "__main__":
    main()
