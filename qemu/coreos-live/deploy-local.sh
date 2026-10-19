#!/usr/bin/env bash
set -euo pipefail

command="${1:-help}"
name="${AGNI_VM_NAME:-agni-coreos}"
state="${XDG_STATE_HOME:-$HOME/.local/state}/agni/qemu/$name"
unit="$HOME/.config/systemd/user/$name.service"
disk="$state/disk.qcow2"
ign="$state/config.ign"
ssh_port="${AGNI_SSH_PORT:-2222}"
wg_port="${AGNI_WG_PORT:-51820}"
memory="${AGNI_RAM_MIB:-2048}"
cpus="${AGNI_CPUS:-2}"

case "$command" in
  install)
    : "${AGNI_COREOS_QCOW2:?Set AGNI_COREOS_QCOW2 to a verified, pinned Fedora CoreOS QEMU qcow2 image}"
    : "${AGNI_IGNITION:?Set AGNI_IGNITION to a rendered and validated Ignition JSON file}"
    test -r "$AGNI_COREOS_QCOW2" && test -r "$AGNI_IGNITION"
    command -v qemu-system-x86_64 >/dev/null
    command -v qemu-img >/dev/null
    test -r /dev/kvm && test -w /dev/kvm || { echo "KVM unavailable for current user" >&2; exit 1; }
    mkdir -p "$state" "$HOME/.config/systemd/user"
    if [[ ! -e "$disk" ]]; then
      qemu-img convert -f qcow2 -O qcow2 "$AGNI_COREOS_QCOW2" "$disk"
    fi
    if [[ ! -e "$ign" ]]; then
      install -m 0600 "$AGNI_IGNITION" "$ign"
    elif ! cmp -s "$AGNI_IGNITION" "$ign"; then
      echo "Existing Ignition differs; first-boot provisioning cannot be reapplied. Refusing replacement." >&2
      exit 1
    fi
    qemu_bin="$(command -v qemu-system-x86_64)"
    cat > "$unit" <<EOF
[Unit]
Description=Agni local Fedora CoreOS QEMU ($name)
After=network.target

[Service]
Type=simple
ExecStart=$qemu_bin -name $name -machine q35,accel=kvm -cpu host -smp $cpus -m $memory -nographic -nodefaults -device virtio-serial-pci -drive if=virtio,format=qcow2,file=$disk -fw_cfg name=opt/com.coreos/config,file=$ign -netdev user,id=net0,hostfwd=tcp:127.0.0.1:$ssh_port-:22,hostfwd=udp:127.0.0.1:$wg_port-:$wg_port -device virtio-net-pci,netdev=net0 -serial mon:stdio
Restart=on-failure
RestartSec=5
TimeoutStopSec=45

[Install]
WantedBy=default.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable --now "$name.service"
    echo "Installed $name; SSH 127.0.0.1:$ssh_port; WireGuard UDP 127.0.0.1:$wg_port"
    ;;
  status) systemctl --user status "$name.service" ;;
  stop) systemctl --user stop "$name.service" ;;
  start) systemctl --user start "$name.service" ;;
  logs) journalctl --user -u "$name.service" -n 100 --no-pager ;;
  *) echo "Usage: agni-coreos-local {install|start|stop|status|logs}; install requires AGNI_COREOS_QCOW2 and AGNI_IGNITION" ;;
esac
