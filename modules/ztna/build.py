"""Stage ztna from a released ztna on PyPI: the Lambda's code (ztna.server = the web console and its API).

    python3 build.py "ztna==0.1.0" <out dir>

    <out dir>/code   ztna plus its deps idlefree-auth / idlefree-ui (boto3 comes with the Lambda runtime)

Terraform runs it at plan time (main.tf). Prints {"code": ...} for Terraform's external data source. No image.
"""
import json
import os
import shutil
import subprocess
import sys


def main():
    spec, out = sys.argv[1], os.path.abspath(sys.argv[2])
    code = os.path.join(out, "code")
    stamp = out + ".stamp"
    # same spec as last time -> reuse (a reinstall gives new file times, so a new zip hash and a Lambda update each plan)
    if not (os.path.isdir(out) and os.path.isfile(stamp) and open(stamp, encoding="utf-8").read() == spec):
        shutil.rmtree(out, ignore_errors=True)
        r = subprocess.run([sys.executable, "-m", "pip", "-q", "--disable-pip-version-check", "install",
                            "--target", code, "--no-compile", spec], capture_output=True, text=True)
        if r.returncode:
            sys.exit(f"build.py: pip failed: {r.stderr.strip()[-500:]}")
        shutil.rmtree(os.path.join(code, "bin"), ignore_errors=True)
        if not os.path.isfile(os.path.join(code, "ztna", "server", "index.html")):
            sys.exit(f"build.py: {spec} has no ztna/server/index.html")
        with open(stamp, "w", encoding="utf-8") as fh:
            fh.write(spec)
    print(json.dumps({"code": code}))


if __name__ == "__main__":
    main()
