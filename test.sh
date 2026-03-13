#!/usr/bin/env bash
# Thurarch — Test the ISO in a QEMU VM
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO=$(ls -t "${SCRIPT_DIR}/out/"*.iso 2>/dev/null | head -1)
VM_DISK="${SCRIPT_DIR}/out/test-disk.qcow2"
OVMF="/usr/share/edk2/x64/OVMF.4m.fd"

if [[ -z "${ISO}" ]]; then
    echo "Error: no ISO found in out/. Run ./build.sh first."
    exit 1
fi

# Create a virtual disk if it doesn't exist
if [[ ! -f "${VM_DISK}" ]]; then
    echo "Creating 64G virtual disk..."
    qemu-img create -f qcow2 "${VM_DISK}" 64G
fi

echo "Booting ISO: ${ISO}"
qemu-system-x86_64 \
    -enable-kvm \
    -m 4G \
    -cpu host \
    -smp 4 \
    -bios "${OVMF}" \
    -drive file="${VM_DISK}",if=none,id=nvme0,format=qcow2 \
    -device nvme,serial=deadbeef,drive=nvme0 \
    -cdrom "${ISO}" \
    -boot d \
    -vga virtio \
    -display gtk
