#!/usr/bin/env bash
# Thurarch — Unattended Arch Linux Installer for ASUS ROG Zephyrus G14 (GA401IV)
set -euo pipefail

# Log everything to console and file
exec > >(tee -i /root/install.log) 2>&1

trap 'echo ""; echo "*** INSTALLATION FAILED — check /root/install.log ***"; exec 1>&2; sleep infinity' ERR

echo "=========================================="
echo "  Thurarch — Unattended Installer"
echo "=========================================="
echo ""

# -------------------------------------------------------------------
# 0. Source configuration
# -------------------------------------------------------------------
source /root/install.conf

DISK="${TARGET_DISK}"
PART1="${DISK}p1"
PART2="${DISK}p2"

if ! lsblk "${DISK}" &>/dev/null; then
    echo "Error: target disk '${DISK}' not found."
    exit 1
fi

echo "[1/12] Partitioning ${DISK}..."

# -------------------------------------------------------------------
# 1. Partition disk
# -------------------------------------------------------------------
sgdisk --zap-all "${DISK}"
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:EFI "${DISK}"
sgdisk -n 2:0:0   -t 2:8300 -c 2:ROOTFS "${DISK}"
partprobe "${DISK}"
udevadm settle --timeout=10

# -------------------------------------------------------------------
# 2. Format partitions
# -------------------------------------------------------------------
echo "[2/12] Formatting partitions..."
mkfs.vfat -F32 -n EFI "${PART1}"
mkfs.btrfs -f -L ROOTFS "${PART2}"

# -------------------------------------------------------------------
# 3. Create btrfs subvolumes
# -------------------------------------------------------------------
echo "[3/12] Creating btrfs subvolumes..."
mount "${PART2}" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@swap

umount /mnt

# -------------------------------------------------------------------
# 4. Mount subvolumes with optimized options
# -------------------------------------------------------------------
echo "[4/12] Mounting subvolumes..."
BTRFS_OPTS="noatime,compress=zstd:3,ssd,discard=async,space_cache=v2,commit=120"

mount -o "subvol=@,${BTRFS_OPTS}" "${PART2}" /mnt
mkdir -p /mnt/{home,.snapshots,swap,boot}
mount -o "subvol=@home,${BTRFS_OPTS}" "${PART2}" /mnt/home
mount -o "subvol=@snapshots,${BTRFS_OPTS}" "${PART2}" /mnt/.snapshots
mount -o "subvol=@swap,nodatacow" "${PART2}" /mnt/swap
mount "${PART1}" /mnt/boot

# Create swapfile
btrfs filesystem mkswapfile --size "${SWAP_SIZE}" /mnt/swap/swapfile
swapon /mnt/swap/swapfile

# -------------------------------------------------------------------
# 5. Pacstrap — install base system
# -------------------------------------------------------------------
echo "[5/12] Installing base system (pacstrap)..."
pacstrap -K /mnt \
    base base-devel linux linux-headers linux-firmware \
    btrfs-progs amd-ucode networkmanager vim git zsh \
    acpi_call-dkms rust power-profiles-daemon

# -------------------------------------------------------------------
# 6. Generate fstab
# -------------------------------------------------------------------
echo "[6/12] Generating fstab..."
genfstab -Lp /mnt >> /mnt/etc/fstab

# -------------------------------------------------------------------
# 7. System configuration (arch-chroot)
# -------------------------------------------------------------------
echo "[7/12] Configuring system..."

arch-chroot /mnt /bin/bash -e <<CHROOT

# Hostname
echo "${HOSTNAME}" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# Timezone
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# Locale
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" > /etc/locale.conf

# Keymap
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# X11 keyboard layout (US International AltGr)
localectl set-x11-keymap us "" altgr-intl

# mkinitcpio — amdgpu early KMS, remove kms hook for NVIDIA
sed -i 's/^MODULES=.*/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
sed -i 's/ kms//' /etc/mkinitcpio.conf
mkinitcpio -P

# systemd-boot
bootctl --esp-path=/boot install

cat > /boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF

cat > /boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /amd-ucode.img
initrd  /initramfs-linux.img
options root=LABEL=ROOTFS rootflags=subvol=@ rw quiet loglevel=3
EOF

# Root password
echo "root:${ROOT_PASSWORD}" | chpasswd

# Create user
useradd -m -G wheel -s /bin/zsh "${USERNAME}"
echo "${USERNAME}:${USER_PASSWORD}" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

# Install Oh My Zsh for the user
sudo -u ${USERNAME} sh -c 'RUNZSH=no CHSH=no sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'

# Enable services
systemctl enable NetworkManager
systemctl enable systemd-timesyncd

CHROOT

# -------------------------------------------------------------------
# 8. NVIDIA setup
# -------------------------------------------------------------------
echo "[8/12] Setting up NVIDIA drivers..."

arch-chroot /mnt /bin/bash -e <<CHROOT

# Enable multilib
sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
pacman -Syu --noconfirm

# Install NVIDIA packages
pacman -S --noconfirm \
    nvidia-open-dkms nvidia-utils lib32-nvidia-utils \
    nvidia-settings nvidia-prime

# NVIDIA modprobe options
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/nvidia.conf <<EOF
options nvidia_drm modeset=1
options nvidia NVreg_DynamicPowerManagement=0x02
EOF

# Rebuild initramfs with NVIDIA
mkinitcpio -P

CHROOT

# -------------------------------------------------------------------
# 9. XFCE + LightDM
# -------------------------------------------------------------------
echo "[9/12] Installing XFCE desktop..."

arch-chroot /mnt /bin/bash -e <<CHROOT

pacman -S --noconfirm \
    xorg-server xfce4 xfce4-goodies \
    lightdm lightdm-gtk-greeter \
    firefox bitwarden ghostty \
    ttf-jetbrains-mono noto-fonts noto-fonts-emoji ttf-liberation

# Remove xfce4-terminal — ghostty replaces it
pacman -Rns --noconfirm xfce4-terminal 2>/dev/null || true

# Set ghostty as the default terminal emulator (system-wide)
mkdir -p /etc/xdg/xfce4
cat > /etc/xdg/xfce4/helpers.rc <<EOF
TerminalEmulator=custom-TerminalEmulator
EOF

mkdir -p /usr/share/xfce4/helpers
cat > /usr/share/xfce4/helpers/custom-TerminalEmulator.desktop <<EOF
[Desktop Entry]
NoDisplay=true
Version=1.0
Encoding=UTF-8
Type=X-XFCE-Helper
X-XFCE-Binaries=ghostty
X-XFCE-Category=TerminalEmulator
X-XFCE-Commands=/usr/bin/ghostty
X-XFCE-CommandsWithParameter=/usr/bin/ghostty -e "%s"
Name=Ghostty
Icon=com.mitchellh.ghostty
EOF

systemctl enable lightdm

CHROOT

# -------------------------------------------------------------------
# 10. ASUS tools (asusctl + supergfxctl via paru)
# -------------------------------------------------------------------
echo "[10/12] Installing ASUS tools..."

arch-chroot /mnt /bin/bash -e <<CHROOT

# Install paru as the regular user (makepkg cannot run as root)
sudo -u ${USERNAME} bash -e <<'PARUEOF'
cd /tmp
git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si --noconfirm
cd /tmp
rm -rf paru
PARUEOF

# Install ASUS packages via paru
sudo -u ${USERNAME} paru -S --noconfirm asusctl supergfxctl

# Enable ASUS services
systemctl enable power-profiles-daemon
systemctl enable supergfxd

# supergfxd configuration
mkdir -p /etc/supergfxd
cat > /etc/supergfxd.conf <<EOF
{
  "mode": "Hybrid",
  "vfio_enable": false,
  "vfio_save": false,
  "always_reboot": false,
  "no_logind": false,
  "logout_timeout_s": 180,
  "hotplug_type": "None"
}
EOF

CHROOT

# -------------------------------------------------------------------
# 11. Snapper + snap-pac (btrfs snapshots)
# -------------------------------------------------------------------
echo "[11/12] Setting up btrfs snapshots (snapper + snap-pac)..."

arch-chroot /mnt /bin/bash -e <<CHROOT

pacman -S --noconfirm snapper snap-pac

# snapper expects to create /.snapshots itself, but we already have
# the @snapshots subvolume mounted there. Unmount, let snapper create
# its config (which recreates the directory), then delete snapper's
# default subvolume and remount ours.
umount /.snapshots
rm -r /.snapshots

snapper -c root create-config /

# snapper create-config creates a .snapshots subvolume inside /
# Remove it — we use our own @snapshots subvolume instead
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount -a

# Allow the user to manage snapshots without root
snapper -c root set-config "ALLOW_USERS=${USERNAME}"

# Configure timeline snapshots
snapper -c root set-config "TIMELINE_CREATE=yes"
snapper -c root set-config "TIMELINE_CLEANUP=yes"
snapper -c root set-config "TIMELINE_MIN_AGE=1800"
snapper -c root set-config "TIMELINE_LIMIT_HOURLY=5"
snapper -c root set-config "TIMELINE_LIMIT_DAILY=7"
snapper -c root set-config "TIMELINE_LIMIT_WEEKLY=0"
snapper -c root set-config "TIMELINE_LIMIT_MONTHLY=0"
snapper -c root set-config "TIMELINE_LIMIT_YEARLY=0"

# Enable snapper timers
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

CHROOT

# -------------------------------------------------------------------
# 11b. WiFi configuration on installed system
# -------------------------------------------------------------------
if [[ -n "${WIFI_SSID}" ]]; then
    echo "[11b/12] Configuring WiFi on installed system..."
    mkdir -p /mnt/etc/NetworkManager/system-connections
    cat > "/mnt/etc/NetworkManager/system-connections/${WIFI_SSID}.nmconnection" <<EOF
[connection]
id=${WIFI_SSID}
type=wifi

[wifi]
ssid=${WIFI_SSID}

[wifi-security]
key-mgmt=wpa-psk
psk=${WIFI_PASSWORD}

[ipv4]
method=auto

[ipv6]
method=auto
EOF
    chmod 600 "/mnt/etc/NetworkManager/system-connections/${WIFI_SSID}.nmconnection"
fi

# -------------------------------------------------------------------
# 12. Cleanup & reboot
# -------------------------------------------------------------------
echo "[12/12] Cleaning up..."

swapoff /mnt/swap/swapfile
umount -R /mnt

echo ""
echo "=========================================="
echo "  Installation complete!"
echo "  Rebooting in 10 seconds..."
echo "  Remove the USB drive!"
echo "=========================================="
sleep 10
reboot
