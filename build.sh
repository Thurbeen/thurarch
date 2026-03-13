#!/usr/bin/env bash
# Thurarch — ISO Builder
# Builds a custom archiso ISO with the unattended installer baked in.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_DIR="${SCRIPT_DIR}/profile"
WORK_DIR="/tmp/thurarch-build"
OUT_DIR="${SCRIPT_DIR}/out"
RELENG="/usr/share/archiso/configs/releng"

# -------------------------------------------------------------------
# Preflight checks
# -------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "Error: must run as root (sudo ./build.sh)"
    exit 1
fi

if ! pacman -Qi archiso &>/dev/null; then
    echo "Installing archiso..."
    pacman -S --noconfirm archiso
fi

if [[ ! -d "${RELENG}" ]]; then
    echo "Error: releng profile not found at ${RELENG}"
    exit 1
fi

# -------------------------------------------------------------------
# Prepare working copy (releng base + our overlay)
# -------------------------------------------------------------------
echo "Preparing build profile..."
WORKPROFILE="${WORK_DIR}/profile"
rm -rf "${WORKPROFILE}"
mkdir -p "${WORKPROFILE}"

# Copy releng as base
cp -rT "${RELENG}" "${WORKPROFILE}"

# Append our extra packages to the package list
if [[ -f "${PROFILE_DIR}/packages.x86_64" ]]; then
    cat "${PROFILE_DIR}/packages.x86_64" >> "${WORKPROFILE}/packages.x86_64"
fi

# Overlay our airootfs on top of releng's
cp -r "${PROFILE_DIR}/airootfs/"* "${WORKPROFILE}/airootfs/"

# Register install script permissions in profiledef.sh (archiso uses this for squashfs)
sed -i '/^file_permissions=(/a\  ["/root/install.sh"]="0:0:755"\n  ["/root/install.conf"]="0:0:644"\n  ["/root/chroot/07-configure.sh"]="0:0:755"\n  ["/root/chroot/08-nvidia.sh"]="0:0:755"\n  ["/root/chroot/09-desktop.sh"]="0:0:755"\n  ["/root/chroot/10-asus.sh"]="0:0:755"\n  ["/root/chroot/11-snapper.sh"]="0:0:755"' "${WORKPROFILE}/profiledef.sh"

# Enable the installer service via symlink
mkdir -p "${WORKPROFILE}/airootfs/etc/systemd/system/multi-user.target.wants"
ln -sf /etc/systemd/system/thurarch-install.service \
    "${WORKPROFILE}/airootfs/etc/systemd/system/multi-user.target.wants/thurarch-install.service"

# -------------------------------------------------------------------
# Generate iwd WiFi profile if WIFI_SSID is set
# -------------------------------------------------------------------
source "${PROFILE_DIR}/airootfs/root/install.conf"

if [[ "${ROOT_PASSWORD}" == "changeme" || "${USER_PASSWORD}" == "changeme" ]]; then
    echo "Error: passwords in install.conf are still set to 'changeme' — update them before building."
    exit 1
fi

if [[ -n "${WIFI_SSID:-}" ]]; then
    echo "Generating iwd WiFi profile for '${WIFI_SSID}'..."
    IWD_DIR="${WORKPROFILE}/airootfs/var/lib/iwd"
    mkdir -p "${IWD_DIR}"
    cat > "${IWD_DIR}/${WIFI_SSID}.psk" <<EOF
[Security]
Passphrase=${WIFI_PASSWORD}
EOF
    chmod 600 "${IWD_DIR}/${WIFI_SSID}.psk"
fi

# -------------------------------------------------------------------
# Build ISO
# -------------------------------------------------------------------
echo "Building ISO..."
mkdir -p "${OUT_DIR}"
mkarchiso -v -w "${WORK_DIR}/work" -o "${OUT_DIR}" "${WORKPROFILE}"

# -------------------------------------------------------------------
# Cleanup
# -------------------------------------------------------------------
echo "Cleaning up build artifacts..."
rm -rf "${WORK_DIR}"

echo ""
echo "Done! ISO written to:"
ls -lh "${OUT_DIR}"/*.iso
