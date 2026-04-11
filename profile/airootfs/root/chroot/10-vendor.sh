#!/usr/bin/env bash
set -euxo pipefail
source /root/install.conf
source /root/chroot/detect-hardware.sh

pacman -S --noconfirm paru

if $IS_ASUS; then
  pacman -S --noconfirm asusctl supergfxctl
  systemctl enable asusd
  systemctl enable supergfxd
fi

# Enable power management
systemctl enable power-profiles-daemon
