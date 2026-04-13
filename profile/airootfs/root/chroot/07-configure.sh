#!/usr/bin/env bash
set -euxo pipefail
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

# mkinitcpio — early KMS for iGPU (hybrid only), NVIDIA modules for dedicated
if [[ "$GPU_MODE" == "hybrid" && "$CPU_VENDOR" == "amd" ]]; then
  sed -i 's/^MODULES=.*/MODULES=(amdgpu)/' /etc/mkinitcpio.conf
elif [[ "$GPU_MODE" == "hybrid" && "$CPU_VENDOR" == "intel" ]]; then
  sed -i 's/^MODULES=.*/MODULES=(i915)/' /etc/mkinitcpio.conf
elif lspci | grep -qi nvidia; then
  sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
fi
sed -i 's/ kms//' /etc/mkinitcpio.conf
# mkinitcpio -P deferred to 08-nvidia.sh (after NVIDIA drivers are installed)

# GRUB (UEFI) with Thurarch Llama theme
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Thurarch --recheck
# Also install to EFI fallback path so firmwares without persistent NVRAM
# (e.g. QEMU OVMF without separate VARS) and post-BIOS-reset hardware still boot.
grub-install --target=x86_64-efi --efi-directory=/boot --removable --recheck

# Install Thurarch GRUB theme (solid #0c121c background, teal #00b4be accent,
# JetBrains Mono typography). Fonts are built from ttf-jetbrains-mono.
mkdir -p /boot/grub/themes/thurarch
cp -r /root/themes/grub-thurarch/. /boot/grub/themes/thurarch/

JBM=/usr/share/fonts/TTF/JetBrainsMono-Regular.ttf
[[ -f $JBM ]] || JBM=$(find /usr/share/fonts -iname 'JetBrainsMono-Regular.ttf' | head -1)
mkdir -p /boot/grub/fonts
for size in 12 14 16 24; do
  grub-mkfont -s "$size" -o "/boot/grub/fonts/jetbrainsmono-${size}.pf2" "$JBM"
done

# /etc/default/grub — kernel cmdline + theme + sane defaults
sed -i \
  -e "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"rootflags=subvol=@ rw quiet loglevel=3\"|" \
  -e "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"root=UUID=${ROOT_UUID}\"|" \
  -e "s|^#\?GRUB_TIMEOUT=.*|GRUB_TIMEOUT=3|" \
  -e "s|^#\?GRUB_GFXMODE=.*|GRUB_GFXMODE=auto|" \
  -e "s|^#\?GRUB_GFXPAYLOAD_LINUX=.*|GRUB_GFXPAYLOAD_LINUX=keep|" \
  -e "s|^#\?GRUB_THEME=.*|GRUB_THEME=\"/boot/grub/themes/thurarch/theme.txt\"|" \
  -e "s|^#\?GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=false|" \
  /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg

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
