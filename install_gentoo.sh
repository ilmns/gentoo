#!/bin/bash

# Set the target NVMe drive for installation
TARGET_DRIVE="/dev/nvme0n1"

# Set the EFI partition mount point
EFI_MOUNT="/mnt/gentoo/boot/efi"

# Set the hostname and timezone
HOSTNAME="gentoo"
TIMEZONE="Europe/Helsinki"

# Set the root password
ROOT_PASSWORD="myrootpassword"

echo "Step 1: Partitioning the NVMe drive"
# Partition the NVMe drive
parted -s "$TARGET_DRIVE" mklabel gpt
parted -s "$TARGET_DRIVE" mkpart primary fat32 1MiB 512MiB
parted -s "$TARGET_DRIVE" set 1 esp on
parted -s "$TARGET_DRIVE" mkpart primary ext4 512MiB 100%
mkfs.fat -F 32 "${TARGET_DRIVE}p1"
mkfs.ext4 "${TARGET_DRIVE}p2"

echo "Step 2: Mounting the partitions"
# Mount the partitions
mount "${TARGET_DRIVE}p2" /mnt/gentoo
mkdir -p "$EFI_MOUNT"
mount "${TARGET_DRIVE}p1" "$EFI_MOUNT"

echo "Step 3: Setting the date"
# Set the date
ntpd -q -g

echo "Step 4: Downloading the Gentoo stage3 tarball"
# Download the Gentoo stage3 tarball
STAGE3_URL="http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64.txt"
STAGE3_FILE=$(wget -qO- "$STAGE3_URL" | grep -Eo 'stage3-amd64-.*\.tar\.xz' | tail -n 1)
STAGE3_URL="http://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3_FILE"
wget "$STAGE3_URL" -O "/mnt/gentoo/$STAGE3_FILE"
tar xvf "/mnt/gentoo/$STAGE3_FILE" -C /mnt/gentoo --xattrs-include='*.*' --numeric-owner
rm "/mnt/gentoo/$STAGE3_FILE"

echo "Step 5: Configuring the Gentoo installation"
# Configure the Gentoo installation
mirrorselect -i -o >> /mnt/gentoo/etc/portage/make.conf
mkdir -p /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
cp -L /etc/resolv.conf /mnt/gentoo/etc/

echo "Step 6: Mounting necessary filesystems"
# Mount necessary filesystems
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev

echo "Step 7: Entering the chroot environment"
# Entering the chroot environment
chroot /mnt/gentoo /bin/bash <<EOF

source /etc/profile
export PS1="(chroot) $PS1"

echo "Step 8: Setting the timezone"
# Set the timezone
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "$TIMEZONE" > /etc/timezone

echo "Step 9: Setting the system clock"
# Set the system clock
hwclock --systohc

echo "Step 10: Configuring the locale"
# Configure the locale
echo "fi_FI.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set fi_FI.utf8

echo "Step 11: Setting the hostname"
# Set the hostname
echo "hostname=\"$HOSTNAME\"" > /etc/conf.d/hostname

echo "Step 12: Setting the root password"
# Set the root password
echo "root:$ROOT_PASSWORD" | chpasswd

echo "Step 13: Installing the Gentoo base system"
# Install the Gentoo base system
emerge-webrsync
emerge --sync
emerge --oneshot sys-apps/portage
emerge --update --deep --newuse @world

echo "Step 14: Configuring the bootloader (GRUB)"
# Configure the bootloader (GRUB)
emerge sys-boot/grub:2
grub-install --target=x86_64-efi --efi-directory="$EFI_MOUNT" --bootloader-id=Gentoo
grub-mkconfig -o /boot/grub/grub.cfg

echo "Step 15: Enabling necessary services"
# Enable necessary services
rc-update add sshd default
rc-update add dhcpcd default

EOF

echo "Step 16: Generating fstab"
# Generate fstab
genfstab -U /mnt/gentoo >> /mnt/gentoo/etc/fstab

echo "Step 17: Exiting the chroot environment"
# Exiting the chroot environment
umount -R /mnt/gentoo/dev
umount -R /mnt/gentoo/sys
umount -R /mnt/gentoo/proc
exit

echo "Step 18: Unmounting filesystems"
# Unmount filesystems
umount "$EFI_MOUNT"
umount /mnt/gentoo

echo "Installation completed. You can now reboot your system."
