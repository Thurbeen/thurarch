#!/usr/bin/env bash
set -euxo pipefail
source /root/install.conf
source /root/chroot/detect-hardware.sh

# Enable multilib
sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf

# Enable Chaotic-AUR (pre-built AUR packages)
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U --noconfirm \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
  'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
cat >>/etc/pacman.conf <<'CHAOTICEOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
CHAOTICEOF

pacman -Syu --noconfirm

# Install NVIDIA packages
# shellcheck disable=SC2046  # Intentionally unquoted: expands to zero args when false
pacman -S --noconfirm \
  nvidia-open nvidia-utils lib32-nvidia-utils \
  nvidia-settings $([[ "$GPU_MODE" == "hybrid" ]] && echo "nvidia-prime")

# NVIDIA modprobe options
mkdir -p /etc/modprobe.d
# fbdev=1 is omitted on hybrid: amdgpu/i915 owns the panel, and forcing nvidia-fbdev
# races the KMS handoff when the dGPU is runtime-suspended (black screen on battery).
if [[ "$GPU_MODE" == "hybrid" ]]; then
  cat >/etc/modprobe.d/nvidia.conf <<EOF
options nvidia_drm modeset=1
options nvidia NVreg_DynamicPowerManagement=0x02
EOF
else
  cat >/etc/modprobe.d/nvidia.conf <<EOF
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_DynamicPowerManagement=0x00
EOF
fi

# Rebuild initramfs with NVIDIA
mkinitcpio -P
