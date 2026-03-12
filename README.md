# Vanilla Arch

Unattended Arch Linux installer ISO for the ASUS ROG Zephyrus G14 (GA401IV).

Boots from USB and automatically installs a fully configured system with zero interaction:
- **btrfs** with subvolumes (@, @home, @snapshots, @swap)
- **systemd-boot**
- **XFCE** + LightDM (X11)
- **NVIDIA** dual GPU (AMD iGPU + RTX 2060 Max-Q via nvidia-open-dkms + nvidia-prime)
- **ASUS tools** (asusctl + supergfxctl for GPU switching and power profiles)

## Prerequisites

- An existing Arch Linux system (or any system with `archiso` available)
- Root access
- Internet connection (packages are downloaded during ISO build and during installation)

## Usage

### 1. Configure

Edit `profile/airootfs/root/install.conf` with your preferences:

```bash
TARGET_DISK="/dev/nvme0n1"    # Target disk (WILL BE WIPED)
HOSTNAME="g14"
USERNAME="magicletur"
USER_PASSWORD="changeme"       # ← Change this!
ROOT_PASSWORD="changeme"       # ← Change this!
TIMEZONE="Europe/Paris"
LOCALE="en_US.UTF-8"
KEYMAP="us"
SWAP_SIZE="16G"
WIFI_SSID=""                   # Set for WiFi auto-connect on the live ISO
WIFI_PASSWORD=""
```

### 2. Build

```bash
sudo ./build.sh
```

The ISO is written to `out/`.

### 3. Flash

```bash
sudo dd bs=4M if=out/vanilla-arch-*.iso of=/dev/sdX conv=fsync oflag=direct status=progress
```

### 4. Boot

Boot the G14 from USB. The installation runs automatically and reboots when done.

## Post-install verification

```bash
# Both GPUs visible
lspci -k | grep -A 3 -E "(VGA|3D)"

# Default renderer is AMD
glxinfo | grep "OpenGL renderer"

# NVIDIA via prime-run
prime-run glxinfo | grep "OpenGL renderer"

# ASUS tools
asusctl -c                     # Battery charge limit
supergfxctl -g                 # Current GPU mode (Hybrid)
supergfxctl -s                 # Supported modes
```

## GPU modes (supergfxctl)

| Mode | Description |
|------|-------------|
| `Hybrid` | Both GPUs active, use `prime-run` for NVIDIA apps |
| `Integrated` | AMD iGPU only (maximum battery life) |

Switch with: `supergfxctl -m <mode>`
