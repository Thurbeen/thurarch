#!/usr/bin/env bash
set -euo pipefail
source /root/install.conf

pacman -S --noconfirm \
    plasma-desktop sddm sddm-kcm kwallet-pam \
    dolphin firefox bitwarden ghostty zed \
    ttf-jetbrains-mono noto-fonts noto-fonts-emoji ttf-liberation

# --- Install Bitwarden extension and pin to Firefox toolbar ---
mkdir -p /usr/lib/firefox/distribution
cat > /usr/lib/firefox/distribution/policies.json <<'EOF'
{
  "policies": {
    "ExtensionSettings": {
      "{446900e4-71c2-419f-a6a7-df9c091e268b}": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi",
        "default_area": "navbar"
      }
    }
  }
}
EOF

# --- Breeze Dark: global theme & color scheme ---
mkdir -p /etc/skel/.config/kdedefaults

cat > /etc/skel/.config/kdeglobals <<'EOF'
[General]
ColorScheme=BreezeDark

[KDE]
LookAndFeelPackage=org.kde.breezedark.desktop
EOF

cp /etc/skel/.config/kdeglobals /etc/skel/.config/kdedefaults/kdeglobals

# --- Breeze Dark: Plasma shell theme (panels, widgets) ---
cat > /etc/skel/.config/plasmarc <<'EOF'
[Theme]
name=breeze-dark
EOF

# --- Wallpaper (applied on first login via plasma-apply-wallpaperimage) ---
mkdir -p /etc/skel/.config/autostart
cat > /etc/skel/.config/autostart/set-wallpaper.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Set Thurarch Wallpaper
Exec=sh -c 'plasma-apply-wallpaperimage /usr/share/backgrounds/thurarch-wallpaper.png && rm ~/.config/autostart/set-wallpaper.desktop'
X-KDE-autostart-phase=2
EOF

# --- Set Zed as default text editor via MIME types ---
cat > /etc/skel/.config/mimeapps.list <<'EOF'
[Default Applications]
text/plain=dev.zed.Zed.desktop
text/x-c=dev.zed.Zed.desktop
text/x-c++=dev.zed.Zed.desktop
text/x-python=dev.zed.Zed.desktop
text/x-shellscript=dev.zed.Zed.desktop
text/x-java=dev.zed.Zed.desktop
text/x-rust=dev.zed.Zed.desktop
text/html=dev.zed.Zed.desktop
text/css=dev.zed.Zed.desktop
text/javascript=dev.zed.Zed.desktop
text/markdown=dev.zed.Zed.desktop
text/xml=dev.zed.Zed.desktop
application/json=dev.zed.Zed.desktop
application/x-yaml=dev.zed.Zed.desktop
application/toml=dev.zed.Zed.desktop
EOF

# --- Copy config to existing user (created in 07-configure.sh before this script) ---
cp -rT /etc/skel/.config "/home/${USERNAME}/.config"
chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.config"

# --- SDDM: use Breeze theme (matches Breeze Dark desktop) ---
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/theme.conf <<'EOF'
[Theme]
Current=breeze
EOF

systemctl enable sddm

# --- KWallet PAM auto-unlock ---
cat > /etc/pam.d/sddm <<'EOF'
auth       include    system-login
auth       optional   pam_kwallet5.so

account    include    system-login

password   include    system-login

session    include    system-login
session    optional   pam_kwallet5.so auto_start
EOF
