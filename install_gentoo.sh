#!/bin/bash

# Set the target NVMe drive for installation
TARGET_DRIVE="/dev/nvme0n1"

# Set the hostname and timezone
HOSTNAME="gentoo"
TIMEZONE="Europe/Helsinki"

# Set the root password
ROOT_PASSWORD="myrootpassword"

# Partition the NVMe drive
parted -s "$TARGET_DRIVE" mklabel gpt
parted -s "$TARGET_DRIVE" mkpart primary ext4 1MiB 100%
parted -s "$TARGET_DRIVE" set 1 boot on
mkfs.ext4 "${TARGET_DRIVE}p1"

# Mount the partition
mount "${TARGET_DRIVE}p1" /mnt/gentoo

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
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
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

# Install the bootloader (GRUB)
emerge sys-boot/grub:2
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Gentoo
grub-mkconfig -o /boot/grub/grub.cfg

EOF

# Unmount filesystems and reboot
umount -R /mnt/gentoo
reboot
