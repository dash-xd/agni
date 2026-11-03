#!/usr/bin/env bash
set -euo pipefail

# Called from the Huram Blacksmith workflow after a Nix-Alpine toolbox build.
: "${QEMU_TOOLBOX_IMAGE:?required}"
: "${QEMU_IMAGE:?required}"
: "${IGNITION_JSON:?required}"
: "${SSH_PRIVATE_KEY:?required}"
MODE="${MODE:-disk}"
LOGIN_USER="${LOGIN_USER:-}"
[[ "$MODE" == disk || "$MODE" == live ]] || { echo "MODE must be disk or live" >&2; exit 1; }
test -f "$QEMU_IMAGE" && test -f "$IGNITION_JSON" && test -f "$SSH_PRIVATE_KEY"

work="$(mktemp -d)"
name="starseed-qemu-$$"
cleanup() {
  docker logs "$name" > "${QEMU_LOG_DIR:-$PWD}/${MODE}-serial.log" 2>&1 || true
  docker rm -f "$name" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT
cp "$IGNITION_JSON" "$work/config.ign"
if [[ "$MODE" == disk ]]; then
  cp "$QEMU_IMAGE" "$work/image.qcow2"
else
  cp "$QEMU_IMAGE" "$work/image.iso"
fi

port="$(python3 - <<'PY'
import socket
with socket.socket() as s:
    s.bind(("127.0.0.1", 0))
    print(s.getsockname()[1])
PY
)"
accel=tcg
device=()
if [[ -c /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
  accel=kvm
  device=(--device /dev/kvm --group-add "$(stat -c %g /dev/kvm)")
elif [[ "${ALLOW_TCG:-false}" != true ]]; then
  echo "Blacksmith runner lacks usable /dev/kvm; qualification cannot pass without KVM (ALLOW_TCG=true for slower local tests)" >&2
  exit 1
fi
boot_args=(-drive file=/work/image.qcow2,format=qcow2,if=virtio
           -fw_cfg name=opt/com.coreos/config,file=/work/config.ign)
if [[ "$MODE" == live ]]; then
  boot_args=(-cdrom /work/image.iso -boot d)
fi
docker run --detach --rm --name "$name" \
  --user "$(id -u):$(id -g)" \
  "${device[@]}" \
  -v "$work:/work:rw" \
  -p "127.0.0.1:${port}:2222" \
  --entrypoint qemu-system-x86_64 \
  "$QEMU_TOOLBOX_IMAGE" \
  -machine q35 -accel "$accel" -m 3072 -smp 2 \
  -display none -monitor none -serial stdio \
  -netdev user,id=n0,hostfwd=tcp::2222-:22 \
  -device virtio-net-pci,netdev=n0 \
  "${boot_args[@]}" >/dev/null

known="$work/known_hosts"
ssh_opts=(-i "$SSH_PRIVATE_KEY" -p "$port" -o IdentitiesOnly=yes
  -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new
  -o UserKnownHostsFile="$known")
ready=false
for _ in $(seq 1 72); do
  if ssh "${ssh_opts[@]}" core@127.0.0.1 true >/dev/null 2>&1; then
    ready=true
    break
  fi
  docker ps --format '{{.Names}}' | grep -Fxq "$name" || break
  sleep 5
done
[[ "$ready" == true ]] || { echo "QEMU $MODE never became SSH-ready" >&2; exit 1; }

ssh "${ssh_opts[@]}" core@127.0.0.1 'bash -se' <<'REMOTE'
set -euo pipefail
test "$(id -un)" = core
test "$(id -u)" != 0
sudo -n true
rpm -q systemd podman crun ignition NetworkManager rpm-ostree afterburn
for pkg in moby-engine containerd runc cifs-utils btrfs-progs clevis clevis-luks clevis-dracut; do
  if rpm -q --quiet "$pkg"; then echo "Unexpected package $pkg" >&2; exit 1; fi
done
podman info >/dev/null
sudo systemd-run --unit=wisp-qemu-smoke --wait --collect /usr/bin/true
sudo systemctl is-failed --quiet wisp-qemu-smoke.service && exit 1 || true
REMOTE
if [[ -n "$LOGIN_USER" ]]; then
  ssh "${ssh_opts[@]}" core@127.0.0.1 "getent passwd '$LOGIN_USER' >/dev/null"
  ssh "${ssh_opts[@]}" "$LOGIN_USER"@127.0.0.1 'test "$(id -u)" -ne 0 && ! sudo -n true'
fi
echo "QUALIFIED mode=$MODE accelerator=$accel login_user=${LOGIN_USER:-none}"
