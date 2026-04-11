#!/usr/bin/env bash
set -euo pipefail
source /root/install.conf
source /root/chroot/detect-hardware.sh

# Hostname
echo "${HOSTNAME}" >/etc/hostname
cat >/etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# Timezone
ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
hwclock --systohc

# Locale
sed -i "s/^#${LOCALE}/${LOCALE}/" /etc/locale.gen
locale-gen
echo "LANG=${LOCALE}" >/etc/locale.conf

# Keymap
echo "KEYMAP=${KEYMAP}" >/etc/vconsole.conf

# X11 keyboard layout (US International AltGr)
localectl set-x11-keymap us "" altgr-intl

# mkinitcpio — early KMS for iGPU (hybrid only), remove kms hook for NVIDIA
if [[ "$GPU_MODE" == "hybrid" && "$CPU_VENDOR" == "amd" ]]; then
  sed -i 's/^MODULES=.*/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
elif [[ "$GPU_MODE" == "hybrid" && "$CPU_VENDOR" == "intel" ]]; then
  sed -i 's/^MODULES=.*/MODULES=(i915)/' /etc/mkinitcpio.conf
else
  sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
fi
sed -i 's/ kms//' /etc/mkinitcpio.conf
mkinitcpio -P

# systemd-boot
bootctl --esp-path=/boot install

cat >/boot/loader/loader.conf <<EOF
default arch.conf
timeout 3
console-mode max
editor no
EOF

cat >/boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /${UCODE_PKG}.img
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
sudo -u "${USERNAME}" sh -c 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'

# Deploy custom .zshrc
cp /root/dotfiles/.zshrc "/home/${USERNAME}/.zshrc"
chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.zshrc"

# Enable services
systemctl enable NetworkManager
systemctl enable systemd-timesyncd
