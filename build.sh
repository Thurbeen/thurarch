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
  cat "${PROFILE_DIR}/packages.x86_64" >>"${WORKPROFILE}/packages.x86_64"
fi

# Overlay our airootfs on top of releng's
cp -r "${PROFILE_DIR}/airootfs/"* "${WORKPROFILE}/airootfs/"

# Register install script permissions in profiledef.sh (archiso uses this for squashfs)
sed -i '/^file_permissions=(/a\  ["/root/install.sh"]="0:0:755"\n  ["/root/install.conf"]="0:0:644"\n  ["/root/chroot/detect-hardware.sh"]="0:0:755"\n  ["/root/chroot/07-configure.sh"]="0:0:755"\n  ["/root/chroot/08-nvidia.sh"]="0:0:755"\n  ["/root/chroot/09-desktop.sh"]="0:0:755"\n  ["/root/chroot/10-vendor.sh"]="0:0:755"\n  ["/root/chroot/11-snapper.sh"]="0:0:755"\n  ["/usr/local/bin/dp-hotplug"]="0:0:755"' "${WORKPROFILE}/profiledef.sh"

# Installer is manual — user runs /root/install.sh after booting the ISO

# -------------------------------------------------------------------
# Collect secrets (interactive prompts)
# -------------------------------------------------------------------
source "${PROFILE_DIR}/airootfs/root/install.conf"

CONF_WORK="${WORKPROFILE}/airootfs/root/install.conf"

echo ""
echo "--- Passwords ---"
read -rsp "Enter password for user '${USERNAME}': " USER_PASSWORD
echo
if [[ -z "${USER_PASSWORD}" ]]; then
  echo "Error: user password cannot be empty."
  exit 1
fi

read -rsp "Enter root password: " ROOT_PASSWORD
echo
if [[ -z "${ROOT_PASSWORD}" ]]; then
  echo "Error: root password cannot be empty."
  exit 1
fi

echo ""
echo "--- WiFi (optional) ---"
read -rp "WiFi SSID (leave empty for Ethernet): " WIFI_SSID
WIFI_SSID="${WIFI_SSID:-}"
WIFI_PASSWORD=""
if [[ -n "${WIFI_SSID}" ]]; then
  read -rsp "WiFi password for '${WIFI_SSID}': " WIFI_PASSWORD
  echo
fi

# Inject secrets into the working-copy install.conf (baked into ISO)
{
  printf 'USER_PASSWORD="%s"\n' "${USER_PASSWORD}"
  printf 'ROOT_PASSWORD="%s"\n' "${ROOT_PASSWORD}"
  printf 'WIFI_SSID="%s"\n' "${WIFI_SSID}"
  printf 'WIFI_PASSWORD="%s"\n' "${WIFI_PASSWORD}"
} >>"${CONF_WORK}"

# -------------------------------------------------------------------
# Generate iwd WiFi profile if WIFI_SSID is set
# -------------------------------------------------------------------
if [[ -n "${WIFI_SSID}" ]]; then
  echo "Generating iwd WiFi profile for '${WIFI_SSID}'..."
  IWD_DIR="${WORKPROFILE}/airootfs/var/lib/iwd"
  mkdir -p "${IWD_DIR}"
  cat >"${IWD_DIR}/${WIFI_SSID}.psk" <<EOF
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
