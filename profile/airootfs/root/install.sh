#!/usr/bin/env bash
# Thurarch — Unattended Arch Linux Installer for ASUS ROG Zephyrus G14 (GA401IV)
set -euo pipefail

trap 'echo ""; echo "*** INSTALLATION FAILED — check: journalctl -u thurarch-install.service ***"; umount -Rl /mnt 2>/dev/null; exec 1>&2; sleep infinity' ERR

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
    acpi_call-dkms power-profiles-daemon openssh

# -------------------------------------------------------------------
# 6. Generate fstab
# -------------------------------------------------------------------
echo "[6/12] Generating fstab..."
genfstab -Lp /mnt >> /mnt/etc/fstab

# Copy chroot scripts, config, and themes into the new system
cp -r /root/chroot /mnt/root/chroot
cp /root/install.conf /mnt/root/install.conf
cp -r /root/themes /mnt/root/themes
mkdir -p /mnt/usr/share/backgrounds
cp /usr/share/backgrounds/thurarch-wallpaper.png /mnt/usr/share/backgrounds/
cp -r /usr/share/color-schemes /mnt/usr/share/color-schemes
cp -r /usr/share/plasma /mnt/usr/share/plasma
cp -r /usr/share/wallpapers /mnt/usr/share/wallpapers
cp -r /usr/share/sddm /mnt/usr/share/sddm

# -------------------------------------------------------------------
# 7. System configuration (arch-chroot)
# -------------------------------------------------------------------
echo "[7/12] Configuring system..."
arch-chroot /mnt /bin/bash /root/chroot/07-configure.sh

# -------------------------------------------------------------------
# 8. NVIDIA setup
# -------------------------------------------------------------------
echo "[8/12] Setting up NVIDIA drivers..."
arch-chroot /mnt /bin/bash /root/chroot/08-nvidia.sh

# -------------------------------------------------------------------
# 9. KDE Plasma + SDDM
# -------------------------------------------------------------------
echo "[9/12] Installing KDE Plasma desktop..."
arch-chroot /mnt /bin/bash /root/chroot/09-desktop.sh

# -------------------------------------------------------------------
# 10. Install paru + ASUS tools (from Chaotic-AUR)
# -------------------------------------------------------------------
echo "[10/12] Installing paru and ASUS tools..."
arch-chroot /mnt /bin/bash /root/chroot/10-asus.sh

# -------------------------------------------------------------------
# 11. Snapper + snap-pac (btrfs snapshots)
# -------------------------------------------------------------------
echo "[11/12] Setting up btrfs snapshots (snapper + snap-pac)..."
arch-chroot /mnt /bin/bash /root/chroot/11-snapper.sh

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

rm -rf /mnt/root/chroot /mnt/root/themes

swapoff /mnt/swap/swapfile 2>/dev/null || true
fuser -km /mnt 2>/dev/null || true
sync
umount -R /mnt || umount -Rl /mnt

echo ""
echo "=========================================="
echo "  Installation complete!"

if [[ "$(systemd-detect-virt)" == "kvm" ]]; then
    echo "  VM detected — shutting down in 5 seconds..."
    echo "=========================================="
    sleep 5
    systemctl poweroff
else
    echo "  Rebooting in 10 seconds..."
    echo "  Remove the USB drive!"
    echo "=========================================="
    sleep 10
    systemctl reboot
fi
