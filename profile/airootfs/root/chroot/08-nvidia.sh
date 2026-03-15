#!/usr/bin/env bash
set -euo pipefail

# Enable multilib
sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf

# Enable Chaotic-AUR (pre-built AUR packages)
pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
pacman-key --lsign-key 3056513887B78AEB
pacman -U --noconfirm \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
cat >> /etc/pacman.conf <<'CHAOTICEOF'

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
CHAOTICEOF

pacman -Syu --noconfirm

# Install NVIDIA packages
pacman -S --noconfirm \
    nvidia-open nvidia-utils lib32-nvidia-utils \
    nvidia-settings nvidia-prime

# NVIDIA modprobe options
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/nvidia.conf <<EOF
options nvidia_drm modeset=1
options nvidia NVreg_DynamicPowerManagement=0x02
EOF

# Rebuild initramfs with NVIDIA
mkinitcpio -P
