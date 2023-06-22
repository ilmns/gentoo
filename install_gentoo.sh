#!/bin/bash

# Set the target disk for installation
TARGET_DISK="/dev/sda"

# Set the hostname and timezone
HOSTNAME="mygentoobox"
TIMEZONE="America/New_York"

# Set the root password
ROOT_PASSWORD="myrootpassword"

# Mount the target disk
mount "$TARGET_DISK" /mnt/gentoo

# Set the date
ntpd -q -g

# Download the Gentoo stage3 tarball
STAGE3_URL="http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64.txt"
STAGE3_FILE=$(wget -qO- "$STAGE3_URL" | grep -Eo 'stage3-amd64-.*\.tar\.xz' | tail -n 1)
STAGE3_URL="http://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3_FILE"
wget "$STAGE3_URL" -P /mnt/gentoo/
tar xpvf "/mnt/gentoo/$STAGE3_FILE" -C /mnt/gentoo --xattrs-include='*.*' --numeric-owner

# Configure the Gentoo installation
mirrorselect -i -o >> /mnt/gentoo/etc/portage/make.conf
mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
cp -L /etc/resolv.conf /mnt/gentoo/etc/

# Mount necessary filesystems
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev

# Chroot into the Gentoo environment
chroot /mnt/gentoo /bin/bash << "EOF"

source /etc/profile
export PS1="(chroot) $PS1"

# Set the timezone
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "$TIMEZONE" > /etc/timezone

# Set the system clock
hwclock --systohc

# Configure the locale
sed -i '/en_US.UTF-8/s/^#//g' /etc/locale.gen
locale-gen
eselect locale set en_US.utf8

# Set the hostname
echo "hostname=\"$HOSTNAME\"" > /etc/conf.d/hostname

# Set the root password
echo "root:$ROOT_PASSWORD" | chpasswd

# Install the Gentoo base system
emerge-webrsync
emerge --sync
emerge --oneshot sys-apps/portage
emerge --update --deep --newuse @world

# Configure the bootloader (GRUB)
emerge sys-boot/grub:2
grub-install "$TARGET_DISK"
grub-mkconfig -o /boot/grub/grub.cfg

EOF

# Unmount filesystems and reboot
umount -R /mnt/gentoo
reboot
