#!/usr/bin/env python3
"""Attested storage qualification for Agni's selected Shoal guests."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import binding

STORE = re.compile(r"/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+\Z")
BUSYBOX = re.compile(r"/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+/bin/busybox\Z")
GUEST_PROBE = r"""set -Eeuo pipefail
mountpoint=/var/mnt/nixstore
test "$(findmnt -rn -o FSTYPE --mountpoint "$mountpoint")" = 9p
options="$(findmnt -rn -o OPTIONS --mountpoint "$mountpoint")"
[[ ",$options," == *,ro,* ]]
store="$mountpoint/$(basename "$SHOAL_PROBE_ROOTFS")"
test -L "$store/bin/sh"
busybox="$(readlink "$store/bin/sh")"
[[ "$busybox" == /nix/store/*/bin/busybox ]]
actual="$(sha256sum "$mountpoint/${busybox#/nix/store/}" | cut -d ' ' -f 1)"
[[ "$actual" == "$SHOAL_EXPECTED_BUSYBOX_SHA256" ]]
test "$(podman info --format '{{.Host.Security.Rootless}}')" = true
boot="$(cat /proc/sys/kernel/random/boot_id)"
for n in a b; do
  scratch="$(mktemp -d)"
  chmod 700 "$scratch"
  cleanup() { podman unshare rm -rf -- "$scratch"; }
  trap cleanup EXIT
  mkdir -p "$scratch/bin" "$scratch/nix/store" "$scratch/tmp"
  ln -s "$SHOAL_PROBE_ROOTFS/bin/sh" "$scratch/bin/sh"
  podman run --rm --network none --pull=never \
    --userns keep-id:uid=1000,gid=1000 --user 1000:1000 \
    --read-only --read-only-tmpfs=false --security-opt label=disable \
    --cap-drop all --security-opt no-new-privileges \
    --mount "type=bind,src=$mountpoint,dst=/nix/store,ro" \
    --rootfs "$scratch" /bin/sh -ec \
      'test -x "$1/bin/sh"; test "$("$2" sha256sum "$2" | "$2" cut -d " " -f 1)" = "$3"; if echo write > /nix/store/shoal-write-probe 2>/dev/null; then exit 1; fi' \
      sh "$SHOAL_PROBE_ROOTFS" "$busybox" "$SHOAL_EXPECTED_BUSYBOX_SHA256"
  cleanup
  trap - EXIT
  echo "SHOAL_GUEST_READER=passed container=$n store=9p-ro"
done
test "$(cat /proc/sys/kernel/random/boot_id)" = "$boot"
echo "SHOAL_GUEST_STORAGE=passed boot=$boot container_readers=2"
"""


def run(argv, script=None, timeout=120):
    completed = subprocess.run(argv, input=script, text=True, capture_output=True,
                               timeout=timeout, check=False)
    if completed.returncode:
        raise ValueError("Command failed (" + str(completed.returncode) + "): " +
                         argv[0] + ": " + completed.stderr[-1200:])
    return completed.stdout.strip()


def writer(scope, machine):
    if not re.fullmatch(r"[a-z][a-z0-9-]{0,39}", scope):
        raise ValueError("Invalid Nix writer scope")
    podman = ["podman", "--connection", machine] if sys.platform == "darwin" else ["podman"]
    mounted = run(podman + ["inspect", scope, "--format",
                             '{{range .Mounts}}{{if eq .Destination "/nix"}}{{.Name}}{{end}}{{end}}'])
    if mounted != scope + "-store":
        raise ValueError("Nix writer does not own the selected store volume")
    return podman + ["exec", scope]


def staged_flake(executor):
    runtime = Path(os.environ.get("NIX_XD_RUNTIME_REPO", ""))
    if not runtime.is_dir():
        raise ValueError("Selected nix.xd checkout required")
    runtime = runtime.resolve()
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,99}", runtime.name):
        raise ValueError("Unsafe infrastructure checkout")
    revision = run(["git", "-C", str(runtime), "rev-parse", "HEAD"])
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Unpinned infrastructure source")
    flake = "/workspaces/" + runtime.name
    if run(executor + ["cat", flake + "/.nix-xd-source-revision"]) != revision:
        raise ValueError("Stage the selected nix.xd revision before storage qualification")
    return flake, revision


def guest_probe(record, ssh_key, rootfs, digest):
    command = ["ssh", "-T", "-i", str(ssh_key), "-p", str(record["sshPort"]),
               "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
               "-o", "StrictHostKeyChecking=yes",
               "-o", "UserKnownHostsFile=" + record["knownHosts"],
               "-o", "ConnectTimeout=8",
               record["sshUser"] + "@" + record["sshHost"],
               "env", "SHOAL_PROBE_ROOTFS=" + rootfs,
               "SHOAL_EXPECTED_BUSYBOX_SHA256=" + digest, "bash", "-se"]
    return run(command, GUEST_PROBE, timeout=180)


def qualify(stage):
    if stage not in ("farcaster", "world1"):
        raise ValueError("Only one Farcaster and one World are supported")
    if os.environ.get("NIX_XD_PROVIDER") != "podman":
        raise ValueError("Shoal QEMU storage gate requires the Podman provider")
    before = binding.bind(stage)
    writer_scope = json.loads(binding.PLAN.read_text())["sharedStore"]["owner"]
    executor = writer(writer_scope, before["machine"])
    flake, revision = staged_flake(executor)
    rootfs = run(executor + ["nix", "build", "--no-link", "--no-write-lock-file",
                             "--print-out-paths", flake + "#storeProbeRootfs^out"], timeout=600)
    if not STORE.fullmatch(rootfs):
        raise ValueError("Unexpected store probe output")
    run(executor + ["test", "-x", rootfs + "/bin/sh"])
    busybox = run(executor + ["readlink", rootfs + "/bin/sh"])
    if not BUSYBOX.fullmatch(busybox):
        raise ValueError("Unexpected BusyBox store executable")
    digest = run(executor + ["sha256sum", busybox]).split()[0]
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("Unexpected BusyBox checksum")
    ssh_key = Path(os.environ.get("SHOAL_SSH_KEY",
                   str(Path.home() / ".ssh/starwisp-test"))).expanduser()
    for name, record in before["bindings"].items():
        result = guest_probe(record, ssh_key, rootfs, digest)
        if result.count("SHOAL_GUEST_READER=passed") != 2 or \
           "SHOAL_GUEST_STORAGE=passed" not in result or \
           "boot=" + record["bootId"] not in result:
            raise ValueError("Incomplete 9P / reader proof for " + name)
        print("AGNI_SHOAL_STORAGE_GUEST=passed placement=" + name + " readers=2", flush=True)
    after = binding.bind(stage)
    if before["bindings"] != after["bindings"] or before["planSha256"] != after["planSha256"]:
        raise ValueError("Physical placement changed during storage qualification")
    receipt = {
        "schemaVersion": 1, "gate": "storage", "result": "passed",
        "stage": stage, "planSha256": before["planSha256"],
        "agniRevision": before["agniRevision"], "nixxdRevision": revision,
        "writerScope": writer_scope, "mount": "read-only-9p",
        "probeRootfs": rootfs, "busyboxSha256": digest,
        "bindings": after["bindings"],
        "readersPerGuest": 2,
        "guestLocalStore": "not-assessed", "network": "not-assessed",
        "services": "not-assessed", "endToEnd": "not-assessed",
    }
    root = Path(os.environ.get("SHOAL_RECEIPT_ROOT",
                str(Path.home() / ".local/state/agni/shoal/receipts"))).expanduser()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    payload = json.dumps(receipt, sort_keys=True, indent=2) + "\n"
    receipt_sha = hashlib.sha256(payload.encode()).hexdigest()
    destination = root / ("storage-" + receipt_sha + ".json")
    with tempfile.NamedTemporaryFile("w", dir=root, prefix=".storage-", delete=False) as handle:
        os.chmod(handle.name, 0o600)
        handle.write(payload)
        pending = Path(handle.name)
    try:
        try:
            os.link(pending, destination)
        except FileExistsError:
            if destination.read_text() != payload:
                raise ValueError("Existing storage evidence digest collision")
    finally:
        pending.unlink(missing_ok=True)
    print("AGNI_SHOAL_STORAGE_RECEIPT=" + str(destination), flush=True)
    print("AGNI_SHOAL_STORAGE=passed stage=" + stage + " nixxd_revision=" + revision +
          " writer=" + writer_scope + " 9p=read-only", flush=True)
    print("AGNI_SHOAL_GUEST_LOCAL_STORE=not-assessed")
    print("AGNI_SHOAL_NETWORK=not-assessed")
    print("AGNI_SHOAL_SERVICES=not-assessed")


if __name__ == "__main__":
    try:
        qualify(os.environ.get("SHOAL_STAGE", "farcaster"))
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as exc:
        print("AGNI_SHOAL_STORAGE=blocked reason=" + str(exc), file=sys.stderr)
        sys.exit(1)
