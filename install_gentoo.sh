#!/bin/bash

# Gentoo Installation Script

# Set the necessary environment variables
export GENTOO_ROOT="/mnt/gentoo"

# Function to check if a command executed successfully
check_command() {
  if [ $? -ne 0 ]; then
    echo "Error: $1"
    exit 1
  fi
}

# Prompt for timezone
read -p "Enter your timezone (e.g., America/New_York): " TIMEZONE

# Prompt for hostname
read -p "Enter your hostname: " HOSTNAME

# Prompt for system profile
echo "Select the system profile:"
eselect profile list
read -p "Enter the number of the desired profile: " PROFILE

# Prompt for partitioning table layout or use default based on OS specifications
echo "Select the partitioning table layout or press Enter to use the default based on OS specifications:"
echo "1. MBR (DOS/BIOS)"
echo "2. GPT (UEFI)"
read -p "Enter the number corresponding to the partitioning table layout: " PART_LAYOUT

# Set the partitioning table layout based on user input or use default
case $PART_LAYOUT in
  1)
    PART_TYPE="msdos"
    ;;
  2)
    PART_TYPE="gpt"
    ;;
  *)
    echo "Using default partitioning table layout based on OS specifications."
    if [ -d "/sys/firmware/efi" ]; then
      PART_TYPE="gpt"
    else
      PART_TYPE="msdos"
    fi
    ;;
esac

# Prompt for filesystem type or use default based on OS specifications
echo "Select the filesystem type for the root partition or press Enter to use the default based on OS specifications:"
echo "1. ext4"
echo "2. btrfs"
echo "3. xfs"
read -p "Enter the number corresponding to the filesystem type: " FS_TYPE

# Set the filesystem type and layout options based on user input or use default
case $FS_TYPE in
  1)
    FILESYSTEM="ext4"
    ;;
  2)
    FILESYSTEM="btrfs"
    ;;
  3)
    FILESYSTEM="xfs"
    ;;
  *)
    echo "Using default filesystem type based on OS specifications."
    FILESYSTEM="ext4"
    ;;
esac

# Mount necessary partitions
mount /dev/nvme0n1p2 $GENTOO_ROOT
check_command "Failed to mount root partition"

# Configure networking
cp /etc/resolv.conf $GENTOO_ROOT/etc/

# Chroot into the Gentoo environment
mount --types proc /proc $GENTOO_ROOT/proc
mount --rbind /sys $GENTOO_ROOT/sys
mount --make-rslave $GENTOO_ROOT/sys
mount --rbind /dev $GENTOO_ROOT/dev
mount --make-rslave $GENTOO_ROOT/dev
chroot $GENTOO_ROOT /bin/bash
check_command "Failed to chroot into Gentoo environment"

# Set the time zone
echo "$TIMEZONE" > /etc/timezone
emerge --config sys-libs/timezone-data
check_command "Failed to set time zone"

# Configure locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set 1

# Configure hostname
echo "$HOSTNAME" > /etc/hostname

# Set the root password
passwd

# Partitioning table layout templates
MBR_LAYOUT="/dev/nvme0n1p1   /boot      ext2    defaults     0 2
/dev/nvme0n1p2   /          $FILESYSTEM    defaults     0 1
/dev/nvme0n1p3   none       swap    sw           0 0"

GPT_LAYOUT="/dev/nvme0n1p1   /boot/efi  vfat    defaults     0 2
/dev/nvme0n1p2   /          $FILESYSTEM    defaults     0 1
/dev/nvme0n1p3   none       swap    sw           0 0"

# Set the partition table layout
if [ "$PART_TYPE" == "msdos" ]; then
  PART_LAYOUT="$MBR_LAYOUT"
elif [ "$PART_TYPE" == "gpt" ]; then
  PART_LAYOUT="$GPT_LAYOUT"
fi

# Set up fstab
echo "$PART_LAYOUT" > /etc/fstab

# Configure make.conf
echo 'MAKEOPTS="-j$(nproc)"' >> /etc/portage/make.conf
echo 'ACCEPT_LICENSE="*"' >> /etc/portage/make.conf

# Update portage and world
emerge --sync
check_command "Failed to sync Portage tree"
emerge --ask --verbose --update --deep --newuse @world
check_command "Failed to update portage and world"

# Configure system services
rc-update add sshd default
rc-update add dhcpcd default

# Configure initramfs
emerge sys-kernel/dracut
check_command "Failed to install dracut"
dracut --kver $(uname -r) initramfs.img
check_command "Failed to configure initramfs"

# Configure system files
echo "hostname=\"$HOSTNAME\"" > /etc/conf.d/hostname
echo 'rc_parallel="NO"' > /etc/rc.conf
echo 'rc_logger="YES"' >> /etc/rc.conf
echo 'rc_depend_strict="YES"' >> /etc/rc.conf
echo 'unicode="YES"' >> /etc/rc.conf

# Configure root filesystem permissions
chmod 700 /root

# Configure portage
mkdir -p /etc/portage/repos.conf
cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf
emerge --oneshot app-eselect/eselect-repository
check_command "Failed to install eselect-repository"
eselect repository add gentoo git https://github.com/gentoo/gentoo.git
check_command "Failed to add Gentoo repository"
emaint sync -r gentoo
check_command "Failed to sync Gentoo repository"
emerge --oneshot portage
check_command "Failed to install portage"

# Configure bootloader
emerge sys-boot/efibootmgr
check_command "Failed to install efibootmgr"
efibootmgr -c -d /dev/nvme0n1 -p 1 -L "Gentoo" -l "\EFI\Gentoo\grubx64.efi"
check_command "Failed to configure bootloader"

# Configure system profile
eselect profile set $PROFILE
check_command "Failed to set system profile"

# Additional system configurations
echo 'sys-apps/mlocate cron' >> /etc/portage/package.use/extra
emerge sys-apps/mlocate
check_command "Failed to install mlocate"

# Additional packages
emerge app-admin/sysklogd
emerge sys-process/cronie
emerge sys-process/at
emerge net-misc/dhcpcd
emerge net-wireless/wpa_supplicant
emerge sys-fs/e2fsprogs
emerge sys-fs/dosfstools
emerge sys-fs/ntfs3g
emerge net-misc/openssh
emerge app-editors/vim
emerge app-misc/tmux
emerge sys-process/htop

# Optional system configurations (choose as needed)
# Configure system logging with syslog-ng
emerge app-admin/syslog-ng
rc-update add syslog-ng default

# Configure firewall with iptables
emerge net-firewall/iptables
rc-update add iptables default

# Configure system monitoring with sysstat
emerge sys-process/sysstat
rc-update add sysstat default

# Optional packages (choose as needed)
emerge app-admin/tmuxinator
emerge app-admin/ansible
emerge app-admin/htop

# Exit chroot and reboot
exit
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount -R /mnt/gentoo
reboot
