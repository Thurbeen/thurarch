#!/usr/bin/env bash
set -euxo pipefail
source /root/install.conf

pacman -S --noconfirm snapper snap-pac

# snapper expects to create /.snapshots itself, but we already have
# the @snapshots subvolume mounted there. Unmount, let snapper create
# its config (which recreates the directory), then delete snapper's
# default subvolume and remount ours.
umount /.snapshots
rm -r /.snapshots

snapper --no-dbus -c root create-config /

# snapper create-config creates a .snapshots subvolume inside /
# Remove it — we use our own @snapshots subvolume instead
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount -a

# Allow the user to manage snapshots without root
snapper --no-dbus -c root set-config "ALLOW_USERS=${USERNAME}"

# Configure timeline snapshots
snapper --no-dbus -c root set-config "TIMELINE_CREATE=yes"
snapper --no-dbus -c root set-config "TIMELINE_CLEANUP=yes"
snapper --no-dbus -c root set-config "TIMELINE_MIN_AGE=1800"
snapper --no-dbus -c root set-config "TIMELINE_LIMIT_HOURLY=5"
snapper --no-dbus -c root set-config "TIMELINE_LIMIT_DAILY=7"
snapper --no-dbus -c root set-config "TIMELINE_LIMIT_WEEKLY=0"
snapper --no-dbus -c root set-config "TIMELINE_LIMIT_MONTHLY=0"
snapper --no-dbus -c root set-config "TIMELINE_LIMIT_YEARLY=0"

# Enable snapper timers
systemctl enable snapper-timeline.timer
systemctl enable snapper-cleanup.timer

# grub-btrfs: regenerate GRUB entries when snapshots change
systemctl enable grub-btrfsd.service
