# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Thurarch is a universal unattended Arch Linux installer ISO builder. It boots from USB and automatically installs a fully configured Arch Linux system with KDE Plasma, NVIDIA GPU support, and a custom "Thurarch Llama" dark theme (teal/cyan accents). Hardware is auto-detected at install time: CPU microcode (Intel/AMD), GPU mode (dedicated/hybrid), and vendor-specific tools (e.g., ASUS asusctl).

## Build & Test Commands

```bash
# Build the ISO (requires root and archiso package)
sudo ./build.sh          # Output: out/vanilla-arch-*.iso

# Test in QEMU VM
./test.sh                # Boot ISO + install to virtual disk
./test.sh --no-iso       # Boot from existing virtual disk only
./test.sh --reset        # Delete virtual disk and start fresh

# Flash to USB
sudo dd bs=4M if=out/vanilla-arch-*.iso of=/dev/sdX status=progress oflag=sync
```

There is no linter, test suite, or CI pipeline. Testing is manual via QEMU.

## Architecture

The system uses **archiso's releng profile** as a base, overlaying custom files from `profile/airootfs/`.

### Boot → Install flow

1. **`build.sh`** assembles the ISO using archiso, copying the airootfs overlay and enabling the installer systemd service
2. On boot, **`thurarch-install.service`** runs `install.sh` non-interactively
3. **`install.sh`** partitions the disk (EFI + btrfs with @, @home, @snapshots, @swap subvolumes), pacstraps the base system, then executes chroot scripts in order

### Chroot scripts (`profile/airootfs/root/chroot/`)

Executed sequentially inside the new system:

| Script | Purpose |
|---|---|
| `detect-hardware.sh` | Sourced helper — sets CPU_VENDOR, UCODE_PKG, GPU_MODE, IS_ASUS, HOSTNAME |
| `07-configure.sh` | Hostname, locale, user creation, oh-my-zsh, NetworkManager |
| `08-nvidia.sh` | NVIDIA open-dkms drivers, Chaotic-AUR repo setup |
| `09-desktop.sh` | KDE Plasma, SDDM, apps (Firefox, Ghostty, Zed, Bitwarden), full Thurarch Llama theme application |
| `10-vendor.sh` | paru AUR helper, conditional ASUS tools (asusctl, supergfxctl) |
| `11-snapper.sh` | Btrfs snapshot management with snapper + snap-pac |

### Configuration

**`profile/airootfs/root/install.conf`** — single config file sourced by install.sh. Contains target disk, hostname, username, passwords, timezone, swap size, and optional WiFi credentials.

### Theme system

The "Thurarch Llama" theme is applied across KDE (color scheme + desktop theme + wallpaper), Ghostty (terminal colors + tab CSS), Zed (JSON theme), Firefox (enterprise policy auto-installs extension), and SDDM. Theme files live in `profile/airootfs/root/themes/` and `profile/airootfs/usr/share/`.

## Key Technical Details

- **Filesystem**: btrfs with zstd compression, SSD-optimized mount options, async discard
- **Boot**: systemd-boot (not GRUB)
- **GPU**: NVIDIA open-dkms; nvidia-prime only installed for hybrid GPU setups (auto-detected)
- **QEMU test VM**: KVM with virtio-vga-gl for GPU acceleration (needed for Ghostty rendering), OVMF EFI firmware, NVMe virtual disk
- **WiFi**: Optional iwd profiles generated at build time by `build.sh`
