#!/usr/bin/env bash
# Thurarch — Test the ISO in a QEMU VM
#
# Usage:
#   ./test.sh              Boot ISO installer (creates disk if needed)
#   ./test.sh --no-iso     Boot from installed disk only
#   ./test.sh --reset      Delete disk and re-run ISO installer
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VM_DISK="${SCRIPT_DIR}/out/test-disk.qcow2"
OVMF="/usr/share/edk2/x64/OVMF.4m.fd"

MODE="${1:-install}"

case "${MODE}" in
  --reset)
    rm -f "${VM_DISK}"
    echo "Deleted ${VM_DISK}"
    MODE="install"
    ;;
  --no-iso)
    if [[ ! -f "${VM_DISK}" ]]; then
      echo "Error: no disk found at ${VM_DISK}. Run ./test.sh first to install."
      exit 1
    fi
    echo "Booting from disk: ${VM_DISK}"
    ;;
  *)
    MODE="install"
    ;;
esac

# shellcheck disable=SC2054  # Commas are QEMU syntax, not array separators
QEMU_ARGS=(
  -enable-kvm
  -m 4G
  -cpu host
  -smp 4
  -bios "${OVMF}"
  -drive file="${VM_DISK}",if=none,id=nvme0,format=qcow2
  -device nvme,serial=deadbeef,drive=nvme0
  -device virtio-vga-gl
  -display gtk,gl=on
)

if [[ "${MODE}" == "install" ]]; then
  ISO=$(find "${SCRIPT_DIR}/out/" -maxdepth 1 -name '*.iso' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
  if [[ -z "${ISO}" ]]; then
    echo "Error: no ISO found in out/. Run ./build.sh first."
    exit 1
  fi
  if [[ ! -f "${VM_DISK}" ]]; then
    echo "Creating 64G virtual disk..."
    qemu-img create -f qcow2 "${VM_DISK}" 64G
  fi
  QEMU_ARGS+=(-cdrom "${ISO}" -boot d)
  echo "Booting ISO: ${ISO}"
fi

qemu-system-x86_64 "${QEMU_ARGS[@]}"

# After installation, automatically boot from disk (skip if --no-iso)
if [[ "${MODE}" == "install" ]]; then
  echo ""
  echo "Installer VM exited. Booting from disk..."
  qemu-system-x86_64 \
    -enable-kvm \
    -m 4G \
    -cpu host \
    -smp 4 \
    -bios "${OVMF}" \
    -drive file="${VM_DISK}",if=none,id=nvme0,format=qcow2 \
    -device nvme,serial=deadbeef,drive=nvme0 \
    -device virtio-vga-gl \
    -display gtk,gl=on
fi
