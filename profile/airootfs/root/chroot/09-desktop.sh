#!/usr/bin/env bash
set -euo pipefail
source /root/install.conf

pacman -S --noconfirm \
    plasma-desktop sddm sddm-kcm \
    firefox bitwarden ghostty \
    ttf-jetbrains-mono noto-fonts noto-fonts-emoji ttf-liberation

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
