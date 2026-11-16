"""Stage lambdachecks for Lambda from a released lambdachecks on PyPI: two packages per architecture.

    python3 build.py "lambdachecks==0.1.0" <out dir>

    <out dir>/server-<arch>   Healthchecks' release (unchanged) + lambdachecks/server (lambda_function.py at the root,
                              local_settings.py as hc/local_settings.py, static files collected + compressed)
                              + its Linux dependencies (Healthchecks' requirements.txt + lambdachecks/server/requirements.txt)
    <out dir>/db-<arch>       s3rds' server (src/db of the s3rds release, unchanged) + its pinned SQLite engine:
                              lambdachecks' database

Needs Docker: dependencies are installed, and Healthchecks' static files collected + compressed (COMPRESS_OFFLINE),
inside AWS's Lambda Python images, so every package matches its runtime (oncalendar ships only as an sdist; pip on
the host cannot build it for Linux). Both architectures are built, so switching architecture needs no rebuild.

Terraform runs it at plan time (main.tf). Prints {"server-arm64": "<dir>", ...} for Terraform's external data source.
Same lambdachecks release as last time -> nothing runs (no Docker needed, no new zip hash); a new release reuses
every step whose inputs did not change.
"""
import json
import os
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request

HEALTHCHECKS = "5.0.3"   # the Healthchecks release lambdachecks runs (its requirements.txt pins Django 6.1.2)
IMAGES = {"server": "public.ecr.aws/lambda/python:3.13",   # the runtimes in main.tf
          "db": "public.ecr.aws/lambda/python:3.12"}       # s3rds' own, the one its compatibility report verified
ARCHS = {"arm64": "linux/arm64", "x86_64": "linux/amd64"}
LIMIT = 250 * 1024 * 1024   # Lambda: unzipped package size


def log(msg):
    print(f"build.py: {msg}", file=sys.stderr)   # stdout is Terraform's JSON


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"build.py: {' '.join(cmd[:4])} ... failed:\n{(r.stdout + r.stderr).strip()[-1500:]}")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def stale(stamp, wanted):
    return not (os.path.isfile(stamp) and read(stamp) == wanted)


def write(stamp, wanted):
    with open(stamp, "w", encoding="utf-8") as f:
        f.write(wanted)


class Build:
    def __init__(self, out):
        self.out = out                                                    # /build in the containers
        self.src = os.path.join(out, "code", "lambdachecks", "server")    # /src (read-only)
        self.app = os.path.join(out, f"healthchecks-{HEALTHCHECKS}")      # the release + hc/local_settings.py + static

    def docker(self, image, arch, script, env=()):
        """script in a Lambda image for arch, <out dir> at /build, lambdachecks/server at /src (read-only)."""
        run(["docker", "run", "--rm", "--platform", ARCHS[arch], "--entrypoint", "/bin/sh",
             "-v", f"{self.out}:/build", "-v", f"{self.src}:/src:ro", *[a for e in env for a in ("-e", e)],
             image, "-c", script])

    def fetch(self, repo, tag, out):
        """A release tarball from GitHub, extracted to out."""
        if os.path.isdir(out):
            return
        log(f"downloading {repo} {tag}")
        tmp = out + ".tmp"
        shutil.rmtree(tmp, ignore_errors=True)
        with urllib.request.urlopen(f"https://github.com/{repo}/archive/refs/tags/{tag}.tar.gz") as r, \
                tarfile.open(fileobj=r, mode="r|gz") as tar:
            tar.extractall(tmp)
        os.rename(os.path.join(tmp, os.listdir(tmp)[0]), out)
        shutil.rmtree(tmp)

    def deps(self, kind, arch, requirements):
        """pip inside the Lambda image for kind; requirements are paths under /build or /src."""
        out = os.path.join(self.out, f"{kind}-deps-{arch}")
        stamp = out + ".stamp"
        mounts = {"/build/": self.out + "/", "/src/": self.src + "/"}   # container path prefix -> host path
        host = [next(h + p[len(c):] for c, h in mounts.items() if p.startswith(c)) for p in requirements]
        wanted = IMAGES[kind] + "\n" + "".join(read(p) for p in host)
        if stale(stamp, wanted):
            log(f"installing {kind} dependencies for {arch} (Docker, first time takes minutes)")
            shutil.rmtree(out, ignore_errors=True)
            # --no-compile: .pyc files would push the server zip over Lambda's 50 MB direct-upload limit
            self.docker(IMAGES[kind], arch, f"pip install -q --no-cache-dir --no-compile --target /build/{kind}-deps-{arch} "
                                            + " ".join(f"-r {p}" for p in requirements))
            write(stamp, wanted)
        return out

    def static(self, arch):
        """collectstatic + compress, as Healthchecks' Dockerfile does, with lambdachecks' settings in place."""
        settings = read(os.path.join(self.src, "local_settings.py"))
        shutil.copy(os.path.join(self.src, "local_settings.py"), os.path.join(self.app, "hc", "local_settings.py"))
        stamp = os.path.join(self.out, "static.stamp")
        if stale(stamp, HEALTHCHECKS + "\n" + settings):
            log("collecting static files (Docker)")
            self.docker(IMAGES["server"], arch,
                        f"cd /build/healthchecks-{HEALTHCHECKS} && python manage.py collectstatic --noinput -v0 "
                        f"&& python manage.py compress -v0",
                        env=[f"PYTHONPATH=/build/server-deps-{arch}", "SECRET_KEY=build-key"])
            write(stamp, HEALTHCHECKS + "\n" + settings)

    def stage(self, name, parts):
        """<out dir>/<name>: the given folders merged, in order."""
        out = os.path.join(self.out, name)
        shutil.rmtree(out, ignore_errors=True)
        os.makedirs(out)
        for part in parts:
            shutil.copytree(part, out, dirs_exist_ok=True,
                            ignore=shutil.ignore_patterns("bin", "__pycache__", ".DS_Store", "requirements.txt"))
        size = sum(os.path.getsize(os.path.join(d, f)) for d, _, files in os.walk(out) for f in files)
        if size > LIMIT:
            sys.exit(f"build.py: {name} is {size // 2**20} MB unzipped, over Lambda's 250 MB")
        return out


def main():
    spec, out = sys.argv[1], os.path.abspath(sys.argv[2])
    result = {f"{kind}-{a}": os.path.join(out, f"{kind}-{a}") for kind in ("server", "db") for a in ARCHS}
    stamp = out + ".stamp"
    # same release as last time -> reuse the staged directories as they are: no Docker, no download, the same zips
    if all(os.path.isdir(d) for d in result.values()) and os.path.isfile(stamp) and read(stamp) == spec:
        print(json.dumps(result))
        return
    os.makedirs(out, exist_ok=True)
    if os.path.isfile(stamp):
        os.remove(stamp)   # written again only once every step below has succeeded

    # the released package, as it is (--no-deps: its dependencies go into the Lambda image's pip below)
    code = os.path.join(out, "code")
    shutil.rmtree(code, ignore_errors=True)
    r = subprocess.run([sys.executable, "-m", "pip", "-q", "--disable-pip-version-check", "install", "--no-compile",
                        "--target", code, "--no-deps", spec], capture_output=True, text=True)
    if r.returncode:
        sys.exit(f"build.py: pip failed: {r.stderr.strip()[-500:]}")
    b = Build(out)

    # s3rds: the server release whose client lambdachecks/server/requirements.txt pins (the same version)
    pin = re.search(r"^s3rds==(\S+)", read(os.path.join(b.src, "requirements.txt")), re.M)
    if not pin:
        sys.exit("build.py: no s3rds==<version> in lambdachecks/server/requirements.txt")
    s3rds = pin.group(1)

    b.fetch("healthchecks/healthchecks", f"v{HEALTHCHECKS}", b.app)
    for d in (".github", "docker", "stuff"):   # what Healthchecks' own image drops too
        shutil.rmtree(os.path.join(b.app, d), ignore_errors=True)
    b.fetch("cloudformer/s3rds", f"v{s3rds}", os.path.join(out, f"s3rds-{s3rds}"))
    server = {a: b.deps("server", a, [f"/build/healthchecks-{HEALTHCHECKS}/requirements.txt", "/src/requirements.txt"])
              for a in ARCHS}
    db = {a: b.deps("db", a, [f"/build/s3rds-{s3rds}/src/db/requirements.txt"]) for a in ARCHS}
    b.static("arm64" if platform.machine() in ("arm64", "aarch64") else "x86_64")   # the host's own, no emulation
    app = os.path.join(out, "server-src")   # lambdachecks/server without local_settings.py (it lives in hc/)
    shutil.rmtree(app, ignore_errors=True)
    os.makedirs(app)
    shutil.copy(os.path.join(b.src, "lambda_function.py"), app)
    for a in ARCHS:
        b.stage(f"server-{a}", [server[a], b.app, app])
        b.stage(f"db-{a}", [db[a], os.path.join(out, f"s3rds-{s3rds}", "src", "db")])
    write(stamp, spec)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
