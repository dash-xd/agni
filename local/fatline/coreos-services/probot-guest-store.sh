#!/usr/bin/env bash
set -Eeuo pipefail

[[ "$(id -u)" != 0 ]] || { echo 'AGNI_PROBOT_GUEST_STORE=blocked reason=requires-rootless-user' >&2; exit 1; }
[[ "$(podman info --format '{{.Host.Security.Rootless}}')" == true ]] || exit 1
[[ "$(findmnt -rn -o FSTYPE --mountpoint /var/mnt/nixstore)" == 9p ]] || exit 1
[[ ",$(findmnt -rn -o OPTIONS --mountpoint /var/mnt/nixstore)," == *,ro,* ]] || exit 1

: "${AGNI_PROBOT_GUEST_EXPECTED_BOOT:?Required expected boot ID}"
[[ "$(< /proc/sys/kernel/random/boot_id)" == "$AGNI_PROBOT_GUEST_EXPECTED_BOOT" ]] || exit 1
: "${AGNI_PROBOT_GUEST_ARTIFACTS:?Required exact non-secret artifact manifest}"

python3 - "$AGNI_PROBOT_GUEST_ARTIFACTS" <<'PY'
import json,os,pathlib,re,sys
artifact=json.loads(pathlib.Path(sys.argv[1]).read_text())
if artifact.get("schema") != 1 or artifact.get("system") != "aarch64-linux" or artifact.get("ghxd_credentials_included") is not False:
    raise SystemExit("Invalid ARM64 non-secret artifact contract")
names={"skymill":"skymill-http","logma":"logma-lifecycle","probot-runtime":"probot"}
if set(artifact.get("artifacts",{})) != set(names):
    raise SystemExit("Incomplete application closure selection")
prefix="/var/mnt/nixstore/"
for name,basename in names.items():
    entry=artifact["artifacts"][name]
    path=entry["store"]
    if not re.fullmatch(r"/nix/store/[a-z0-9]{32}-"+re.escape(basename),path):
        raise SystemExit("Malformed Nix store path")
    if not re.fullmatch(r"[a-f0-9]{40}",entry.get("revision","")):
        raise SystemExit("Invalid component revision")
    guest=path.replace("/nix/store/",prefix,1)
    target=pathlib.Path(guest)
    if name == "probot-runtime":
        ok=(target/"router/serve.js").is_file()
    else:
        ok=target.is_file() and os.access(target,os.X_OK)
    if not ok:
        raise SystemExit("Guest cannot read pinned "+name+" artifact")
    print("AGNI_PROBOT_GUEST_ARTIFACT=passed component="+name+" sha="+entry["revision"])
node=artifact.get("node","")
if not re.fullmatch(r"/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+/bin/node",node):
    raise SystemExit("Invalid store-backed Node runtime")
guest_node=pathlib.Path(node.replace("/nix/store/",prefix,1))
if not guest_node.is_file() or not os.access(guest_node,os.X_OK):
    raise SystemExit("Node runtime not visible via read-only 9P")
print("AGNI_PROBOT_GUEST_STORE=passed roles=3 node=visible mount=9p-ro")
PY
