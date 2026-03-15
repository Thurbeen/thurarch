#!/usr/bin/env bash
set -euo pipefail
source /root/install.conf

pacman -S --noconfirm \
    plasma-desktop plasma-nm bluedevil bluez bluez-utils sddm sddm-kcm kwallet-pam \
    dolphin firefox bitwarden ghostty zed \
    ttf-jetbrains-mono noto-fonts noto-fonts-emoji ttf-liberation \
    pipewire pipewire-pulse pipewire-alsa wireplumber plasma-pa

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
      },
      "thurarch-llama-theme@magicletur": {
        "installation_mode": "normal_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/thurarch-llama/latest.xpi"
      }
    }
  }
}
EOF

# --- Thurarch Llama: global theme & color scheme ---
mkdir -p /etc/skel/.config/kdedefaults

cat > /etc/skel/.config/kdeglobals <<'EOF'
[General]
ColorScheme=ThurarchLlama

[KDE]
LookAndFeelPackage=org.thurarch.llama.desktop

[Icons]
Theme=breeze-dark
EOF

cp /etc/skel/.config/kdeglobals /etc/skel/.config/kdedefaults/kdeglobals

# --- Thurarch Llama: Plasma shell theme (panels, widgets) ---
cat > /etc/skel/.config/plasmarc <<'EOF'
[Theme]
name=thurarch-llama
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

# --- Ghostty theme ---
mkdir -p /etc/skel/.config/ghostty/themes
cp /root/themes/ThurarchLlama.ghostty /etc/skel/.config/ghostty/themes/ThurarchLlama
cp /root/themes/ghostty-tabs.css /etc/skel/.config/ghostty/ghostty-tabs.css
cat > /etc/skel/.config/ghostty/config <<'EOF'
theme = ThurarchLlama
gtk-custom-css = ghostty-tabs.css
EOF

# --- Zed theme & settings ---
mkdir -p /etc/skel/.config/zed/themes
cp /root/themes/ThurarchLlama.json /etc/skel/.config/zed/themes/ThurarchLlama.json
cat > /etc/skel/.config/zed/settings.json <<'EOF'
{
  "theme": {
    "mode": "dark",
    "dark": "Thurarch Llama"
  }
}
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

# --- KDE shortcut: Meta+Up to maximize window ---
cat > /etc/skel/.config/kglobalshortcutsrc <<'EOF'
[kwin]
Window Maximize=Meta+Up\t,Meta+PgUp,Maximize Window
EOF

# --- Git config ---
cat > /etc/skel/.gitconfig <<'EOF'
[user]
	email = magicletur@protonmail.com
	name = letur
	signingkey = ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGuvFW1oLxzgwx8ZgC9vQAukGPiIESqARG9Ildk40tQU
[gpg]
	format = ssh
[commit]
	gpgsign = true
[core]
	editor = vim
EOF

# --- Copy config to existing user (created in 07-configure.sh before this script) ---
cp -rT /etc/skel/.config "/home/${USERNAME}/.config"
cp /etc/skel/.gitconfig "/home/${USERNAME}/.gitconfig"
chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.config"
chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.gitconfig"

# --- SDDM: use Breeze theme with Thurarch Llama wallpaper ---
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/theme.conf <<'EOF'
[Theme]
Current=breeze
EOF

cat > /usr/share/sddm/themes/breeze/theme.conf.user <<'EOF'
[General]
background=thurarch-llama-wallpaper.png
type=image
EOF

systemctl enable sddm
systemctl enable bluetooth

# --- KWallet PAM auto-unlock ---
cat > /etc/pam.d/sddm <<'EOF'
auth       include    system-login
auth       optional   pam_kwallet5.so

account    include    system-login

password   include    system-login

session    include    system-login
session    optional   pam_kwallet5.so auto_start
EOF
