#!/usr/bin/env bash
# detect-hardware.sh — Sourced by install scripts to set hardware environment variables.
# Sets: CPU_VENDOR, UCODE_PKG, GPU_MODE, IS_ASUS, HOSTNAME (fallback)

# CPU detection
if grep -q "GenuineIntel" /proc/cpuinfo; then
    CPU_VENDOR="intel"
    UCODE_PKG="intel-ucode"
else
    CPU_VENDOR="amd"
    UCODE_PKG="amd-ucode"
fi

# GPU detection — count VGA/3D controllers
gpu_count=$(lspci | grep -cE "VGA|3D" || true)
if [[ "$gpu_count" -gt 1 ]]; then
    GPU_MODE="hybrid"
else
    GPU_MODE="dedicated"
fi

# Vendor detection
if grep -qi "ASUSTeK" /sys/class/dmi/id/sys_vendor 2>/dev/null; then
    IS_ASUS=true
else
    IS_ASUS=false
fi

# Hostname fallback (auto-detect from DMI if not set in install.conf)
if [[ -z "${HOSTNAME:-}" ]]; then
    HOSTNAME=$(tr ' ' '-' < /sys/class/dmi/id/product_name 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
    HOSTNAME="${HOSTNAME:-archlinux}"
fi
