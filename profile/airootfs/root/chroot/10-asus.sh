#!/usr/bin/env bash
set -euo pipefail

pacman -S --noconfirm paru asusctl supergfxctl

# Enable ASUS services
systemctl enable asusd
systemctl enable supergfxd

# Enable power management
systemctl enable power-profiles-daemon
