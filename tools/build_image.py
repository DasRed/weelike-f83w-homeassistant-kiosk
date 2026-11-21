#!/usr/bin/env python3
"""
Builds the F83W system image from the original GSI and the files in src/.

Steps:
  1. Download the GSI and the Home Assistant app (build/sources.json, SHA-256 verified)
  2. Grow the ext4 image and resolve shared_blocks (otherwise it is not writable)
  3. Modify it with debugfs:
       - remove the apps listed in src/removed-apps.txt
       - add the Home Assistant app as a system app (libraries extracted to lib/arm/)
       - write the files from src/system-files.txt (mode, owner, SELinux label)
       - apply src/system/bin/rw-system.sh.patch to /system/bin/rw-system.sh
       - append src/product/build.prop.append to /system/product/etc/build.prop
  4. Check the file system and shrink it to its minimum size
  5. Optionally compress with xz, write SHA256SUMS

Runs on Linux (GitHub Actions: ubuntu-latest) and needs e2fsprogs (debugfs,
e2fsck, resize2fs), patch and xz. No root, no loop mounts.

Usage: build_image.py --version v8 [--out out] [--cache .cache] [--xz]
"""
import argparse
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
HA_DIR = "/system/app/HomeAssistant"
HA_ABI = "armeabi-v7a"  # 32-bit userspace -> lib/arm/
GROW = 200 * 1024 * 1024


def log(msg):
    print(f"==> {msg}", flush=True)


def run(cmd, ok=(0,), **kw):
    res = subprocess.run(cmd, **kw)
    if res.returncode not in ok:
        sys.exit(f"Error: {' '.join(cmd)} -> exit code {res.returncode}")
    return res


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(entry, cache):
    os.makedirs(cache, exist_ok=True)
    dest = os.path.join(cache, entry["file"])
    if os.path.exists(dest) and sha256(dest) == entry["sha256"]:
        log(f"from cache: {entry['file']}")
        return dest
    log(f"downloading {entry['url']}")
    req = urllib.request.Request(entry["url"], headers={"User-Agent": "curl/8"})
    with urllib.request.urlopen(req) as r, open(dest + ".part", "wb") as f:
        shutil.copyfileobj(r, f, 1 << 20)
    got = sha256(dest + ".part")
    if got != entry["sha256"]:
        sys.exit(f"Checksum mismatch for {entry['file']}: {got} instead of {entry['sha256']}")
    os.replace(dest + ".part", dest)
    return dest


def debugfs_read(img, request):
    return subprocess.run(["debugfs", "-R", request, img], capture_output=True, text=True, check=True).stdout


def exists(img, path):
    res = subprocess.run(["debugfs", "-R", f"stat {path}", img], capture_output=True, text=True)
    return "Inode:" in res.stdout


def tree(img, path):
    """Entries below path (recursive) as a list of (path, is_dir), children before parents."""
    out = []
    for line in debugfs_read(img, f"ls -p {path}").splitlines():
        parts = line.strip().split("/")
        if len(parts) < 7:
            continue
        mode, name = int(parts[2], 8), parts[5]
        if name in (".", ".."):
            continue
        child = f"{path}/{name}"
        if (mode & 0o170000) == 0o040000:
            out += tree(img, child)
            out.append((child, True))
        else:
            out.append((child, False))
    return out


class Commands:
    """Collects debugfs commands and runs them in a single pass."""

    def __init__(self, work):
        self.work = work
        self.lines = []
        self.labels = {}

    def label_file(self, selinux_type):
        if selinux_type not in self.labels:
            path = os.path.join(self.work, f"label-{selinux_type}")
            with open(path, "wb") as f:
                f.write(f"u:object_r:{selinux_type}:s0".encode() + b"\0")
            self.labels[selinux_type] = path
        return self.labels[selinux_type]

    def meta(self, path, filetype, mode, uid, gid, selinux_type):
        self.lines += [
            f"sif {path} mode 0{filetype}{mode[-4:]}",
            f"sif {path} uid {uid}",
            f"sif {path} gid {gid}",
            f"ea_set -f {self.label_file(selinux_type)} {path} security.selinux",
        ]

    def mkdir(self, path, mode="0755", uid=0, gid=0, selinux_type="system_file"):
        self.lines.append(f"mkdir {path}")
        self.meta(path, "4", mode, uid, gid, selinux_type)

    def write(self, host, path, mode="0644", uid=0, gid=0, selinux_type="system_file"):
        parent, name = path.rsplit("/", 1)
        self.lines += [f"cd {parent}", f"write {host} {name}", "cd /"]
        self.meta(path, "10", mode, uid, gid, selinux_type)

    def replace(self, host, path, mode, uid, gid, selinux_type):
        self.lines.append(f"rm {path}")
        self.write(host, path, mode, uid, gid, selinux_type)

    def run(self, img):
        script = os.path.join(self.work, "debugfs.cmd")
        with open(script, "w") as f:
            f.write("\n".join(self.lines) + "\n")
        res = subprocess.run(["debugfs", "-w", "-f", script, img], capture_output=True, text=True)
        errors = [l for l in res.stderr.splitlines() if l.strip() and not l.startswith("debugfs ")]
        if res.returncode != 0 or errors:
            sys.exit("debugfs reported errors:\n" + "\n".join(errors))


def read_table(path):
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                rows.append(line.split())
    return rows


def build(args):
    with open(os.path.join(ROOT, "build", "sources.json")) as f:
        sources = json.load(f)
    os.makedirs(args.out, exist_ok=True)
    name = f"{sources['image_name']}-{args.version}.img"
    img = os.path.join(args.out, name)
    work = tempfile.mkdtemp(prefix="f83w-build-")

    gsi = fetch(sources["gsi"], args.cache)
    apk = fetch(sources["homeassistant"], args.cache)

    log("unpacking GSI")
    with gzip.open(gsi, "rb") as src, open(img, "wb") as dst:
        shutil.copyfileobj(src, dst, 1 << 20)

    log("growing image and resolving shared_blocks")
    with open(img, "r+b") as f:
        f.truncate(os.path.getsize(img) + GROW)
    run(["resize2fs", img], stdout=subprocess.DEVNULL)
    run(["e2fsck", "-fy", "-E", "unshare_blocks", img], ok=(0, 1), stdout=subprocess.DEVNULL)

    cmd = Commands(work)

    log("removing apps")
    with open(os.path.join(SRC, "removed-apps.txt")) as f:
        removed = [l.strip() for l in f if l.strip() and not l.startswith("#")]
    for app in removed:
        if not exists(img, app):
            sys.exit(f"{app} does not exist in the GSI (check removed-apps.txt)")
        for path, is_dir in tree(img, app):
            cmd.lines.append(f"{'rmdir' if is_dir else 'rm'} {path}")
        cmd.lines.append(f"rmdir {app}")

    log(f"Home Assistant {sources['homeassistant']['version']} as system app")
    cmd.mkdir(HA_DIR)
    cmd.write(apk, f"{HA_DIR}/HomeAssistant.apk")
    cmd.mkdir(f"{HA_DIR}/lib")
    cmd.mkdir(f"{HA_DIR}/lib/arm")
    libdir = os.path.join(work, "lib")
    os.makedirs(libdir)
    with zipfile.ZipFile(apk) as z:
        libs = [n for n in z.namelist() if n.startswith(f"lib/{HA_ABI}/") and n.endswith(".so")]
        if not libs:
            sys.exit(f"no {HA_ABI} libraries found in the app")
        for member in sorted(libs):
            host = os.path.join(libdir, os.path.basename(member))
            with z.open(member) as s, open(host, "wb") as d:
                shutil.copyfileobj(s, d)
            cmd.write(host, f"{HA_DIR}/lib/arm/{os.path.basename(member)}")

    log("files from src/system-files.txt")
    for target, source, mode, uid, gid, selinux_type in read_table(os.path.join(SRC, "system-files.txt")):
        if target.endswith("/"):
            cmd.mkdir(target.rstrip("/"), mode, uid, gid, selinux_type)
        else:
            cmd.write(os.path.join(SRC, source), target, mode, uid, gid, selinux_type)

    log("patching rw-system.sh")
    rw = os.path.join(work, "rw-system.sh")
    run(["debugfs", "-R", f"dump /system/bin/rw-system.sh {rw}", img], stderr=subprocess.DEVNULL)
    run(["patch", "--no-backup-if-mismatch", "-s", rw, os.path.join(SRC, "system", "bin", "rw-system.sh.patch")])
    cmd.replace(rw, "/system/bin/rw-system.sh", "0755", 0, 2000, "phhsu_exec")

    log("extending build.prop")
    prop = os.path.join(work, "build.prop")
    run(["debugfs", "-R", f"dump /system/product/etc/build.prop {prop}", img], stderr=subprocess.DEVNULL)
    with open(os.path.join(SRC, "product", "build.prop.append")) as s, open(prop, "a") as d:
        d.write("\n" + s.read())
    cmd.replace(prop, "/system/product/etc/build.prop", "0644", 0, 0, "system_file")

    log("running debugfs")
    cmd.run(img)

    log("checking and shrinking the file system")
    run(["e2fsck", "-fy", img], ok=(0, 1), stdout=subprocess.DEVNULL)
    run(["resize2fs", "-M", img], stdout=subprocess.DEVNULL)
    run(["e2fsck", "-fn", img], stdout=subprocess.DEVNULL)

    files = [name]
    if args.xz:
        log("compressing with xz")
        run(["xz", "-T0", "-6", "-k", "-f", img])
        files.append(name + ".xz")

    with open(os.path.join(args.out, "SHA256SUMS"), "w") as f:
        for n in files:
            f.write(f"{sha256(os.path.join(args.out, n))}  {n}\n")
    shutil.rmtree(work)
    log(f"done: {img} ({os.path.getsize(img) // (1024 * 1024)} MB)")


def main():
    p = argparse.ArgumentParser(description="Builds the F83W system image")
    p.add_argument("--version", required=True, help="image version, e.g. v8")
    p.add_argument("--out", default=os.path.join(ROOT, "out"))
    p.add_argument("--cache", default=os.path.join(ROOT, ".cache"))
    p.add_argument("--xz", action="store_true", help="also create .img.xz")
    build(p.parse_args())


if __name__ == "__main__":
    main()
