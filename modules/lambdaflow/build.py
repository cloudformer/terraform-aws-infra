"""Stage lambdaflow for Lambda from a released lambdaflow on PyPI: the server code and its layer.

    python3 build.py "lambdaflow==0.1.1" "jinja2==3.1.6 tzdata==2025.2" <out dir>

    <out dir>/code   lambdaflow itself (--no-deps); the zip is code/lambdaflow/server, the directory the server runs
                     from (its modules, and the airflow shim DAG files import, are plain top-level names)
    <out dir>/layer  python/<packages>: the layer's pins, as Linux arm64 wheels for Python 3.12

Terraform runs it at plan time (main.tf). Prints {"code": ..., "layer": ...} for Terraform's external data source.
"""
import json
import os
import shutil
import subprocess
import sys

# the Lambdas: runtime python3.12, architecture arm64 (main.tf)
PLATFORM = ["--platform", "manylinux2014_aarch64", "--implementation", "cp", "--python-version", "3.12",
            "--only-binary=:all:"]


def pip(*args):
    # no .pyc: they embed timestamps, the zip hash would change every plan
    r = subprocess.run([sys.executable, "-m", "pip", "-q", "--disable-pip-version-check", "install", "--no-compile",
                        *args], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"build.py: pip failed: {r.stderr.strip()[-500:]}")


def main():
    spec, layer_packages, out = sys.argv[1], sys.argv[2], os.path.abspath(sys.argv[3])
    code, layer = os.path.join(out, "code"), os.path.join(out, "layer")
    result = json.dumps({"code": os.path.join(code, "lambdaflow", "server"), "layer": layer})
    stamp, key = out + ".stamp", f"{spec} | {layer_packages}"
    # same inputs as last time -> reuse the directories as they are (a reinstall gives new file times, so new zip
    # hashes, a new layer version and Lambda updates on every plan)
    if os.path.isdir(out) and os.path.isfile(stamp) and open(stamp, encoding="utf-8").read() == key:
        print(result)
        return
    shutil.rmtree(out, ignore_errors=True)
    pip("--target", code, "--no-deps", spec)
    pip("--target", os.path.join(layer, "python"), *PLATFORM, *layer_packages.split())
    shutil.rmtree(os.path.join(code, "bin"), ignore_errors=True)
    with open(stamp, "w", encoding="utf-8") as fh:
        fh.write(key)
    print(result)


if __name__ == "__main__":
    main()
