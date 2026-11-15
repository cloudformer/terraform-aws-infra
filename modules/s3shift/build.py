"""Stage s3shift for Lambda from a released s3shift on PyPI: the server code and its layer.

    python3 build.py "s3shift==0.1.2" <out dir>

    <out dir>/code   s3shift itself (--no-deps); the zip is code/s3shift/server, the directory the server runs from
                     (its modules import each other by plain name, as when it ran from the repo)
    <out dir>/layer  python/<packages>: the pins in s3shift/server/requirements.txt (DuckDB, the MySQL and Postgres
                     clients), as Linux x86_64 wheels for Python 3.12

Terraform runs it at plan time (main.tf). Prints {"code": ..., "layer": ...} for Terraform's external data source.
"""
import json
import os
import shutil
import subprocess
import sys

# the Lambda: runtime python3.12, architecture x86_64 (main.tf)
PLATFORM = ["--platform", "manylinux_2_28_x86_64", "--platform", "manylinux2014_x86_64", "--implementation", "cp",
            "--python-version", "3.12", "--only-binary=:all:"]


def pip(*args):
    # no .pyc: they embed timestamps, the zip hash would change every plan
    r = subprocess.run([sys.executable, "-m", "pip", "-q", "--disable-pip-version-check", "install", "--no-compile",
                        *args], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"build.py: pip failed: {r.stderr.strip()[-500:]}")


def main():
    spec, out = sys.argv[1], os.path.abspath(sys.argv[2])
    code, layer = os.path.join(out, "code"), os.path.join(out, "layer")
    result = json.dumps({"code": os.path.join(code, "s3shift", "server"), "layer": layer})
    stamp = out + ".stamp"
    # same spec as last time -> reuse the directories as they are (a reinstall gives new file times, so new zip
    # hashes, a new layer version and a Lambda update on every plan)
    if os.path.isdir(out) and os.path.isfile(stamp) and open(stamp, encoding="utf-8").read() == spec:
        print(result)
        return
    shutil.rmtree(out, ignore_errors=True)
    pip("--target", code, "--no-deps", spec)
    pip("--target", os.path.join(layer, "python"), *PLATFORM,
        "-r", os.path.join(code, "s3shift", "server", "requirements.txt"))
    shutil.rmtree(os.path.join(code, "bin"), ignore_errors=True)
    with open(stamp, "w", encoding="utf-8") as fh:
        fh.write(spec)
    print(result)


if __name__ == "__main__":
    main()
