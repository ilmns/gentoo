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

# Function to run a command and check for errors
run_command() {
  echo "Running command: $1"
  eval "$1"
  check_command "$1"
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
run_command "mount /dev/nvme0n1p2 $GENTOO_ROOT"

# Configure networking
run_command "cp /etc/resolv.conf $GENTOO_ROOT/etc/"
run_command "mount --types proc /proc $GENTOO_ROOT/proc"
run_command "mount --rbind /sys $GENTOO_ROOT/sys"
run_command "mount --make-rslave $GENTOO_ROOT/sys"
run_command "mount --rbind /dev $GENTOO_ROOT/dev"
run_command "mount --make-rslave $GENTOO_ROOT/dev"

# Chroot into the Gentoo environment
run_command "chroot $GENTOO_ROOT /bin/bash"

# Set the time zone
run_command "echo \"$TIMEZONE\" > /etc/timezone"
run_command "emerge --config sys-libs/timezone-data"

# Configure locale
run_command "echo \"en_US.UTF-8 UTF-8\" >> /etc/locale.gen"
run_command "locale-gen"
run_command "eselect locale set 1"

# Configure hostname
run_command "echo \"$HOSTNAME\" > /etc/hostname"

# Set the root password
run_command "passwd"

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
run_command "echo \"$PART_LAYOUT\" > /etc/fstab"

# Configure make.conf
run_command "echo 'MAKEOPTS=\"-j$(nproc)\"' >> /etc/portage/make.conf"
run_command "echo 'ACCEPT_LICENSE=\"*\"' >> /etc/portage/make.conf"

# Update portage and world
run_command "emerge --sync"
run_command "emerge --ask --verbose --update --deep --newuse @world"

# Configure system services
run_command "rc-update add sshd default"
run_command "rc-update add dhcpcd default"

# Configure initramfs
run_command "emerge sys-kernel/dracut"
run_command "dracut --kver $(uname -r) initramfs.img"

# Configure system files
run_command "echo \"hostname=\\\"$HOSTNAME\\\"\" > /etc/conf.d/hostname"
run_command "echo 'rc_parallel=\"NO\"' > /etc/rc.conf"
run_command "echo 'rc_logger=\"YES\"' >> /etc/rc.conf"
run_command "echo 'rc_depend_strict=\"YES\"' >> /etc/rc.conf"
run_command "echo 'unicode=\"YES\"' >> /etc/rc.conf"

# Configure root filesystem permissions
run_command "chmod 700 /root"

# Configure portage
run_command "mkdir -p /etc/portage/repos.conf"
run_command "cp /usr/share/portage/config/repos.conf /etc/portage/repos.conf/gentoo.conf"
run_command "emerge --oneshot app-eselect/eselect-repository"
run_command "eselect repository add gentoo git https://github.com/gentoo/gentoo.git"
run_command "emaint sync -r gentoo"
run_command "emerge --oneshot portage"

# Configure bootloader
run_command "emerge sys-boot/efibootmgr"
run_command "efibootmgr -c -d /dev/nvme0n1 -p 1 -L \"Gentoo\" -l \"\\EFI\\Gentoo\\grubx64.efi\""

# Configure system profile
run_command "eselect profile set $PROFILE"

# Additional system configurations
run_command "echo 'sys-apps/mlocate cron' >> /etc/portage/package.use/extra"
run_command "emerge sys-apps/mlocate"

# Additional packages
run_command "emerge app-admin/sysklogd"
run_command "emerge sys-process/cronie"
run_command "emerge sys-process/at"
run_command "emerge net-misc/dhcpcd"
run_command "emerge net-wireless/wpa_supplicant"
run_command "emerge sys-fs/e2fsprogs"
run_command "emerge sys-fs/dosfstools"
run_command "emerge sys-fs/ntfs3g"
run_command "emerge net-misc/openssh"
run_command "emerge app-editors/vim"
run_command "emerge app-misc/tmux"
run_command "emerge sys-process/htop"

# Optional system configurations (choose as needed)
# Configure system logging with syslog-ng
run_command "emerge app-admin/syslog-ng"
run_command "rc-update add syslog-ng default"

# Configure firewall with iptables
run_command "emerge net-firewall/iptables"
run_command "rc-update add iptables default"

# Configure system monitoring with sysstat
run_command "emerge sys-process/sysstat"
run_command "rc-update add sysstat default"

# Optional packages (choose as needed)
run_command "emerge app-admin/tmuxinator"
run_command "emerge app-admin/ansible"
run_command "emerge app-admin/htop"

# Exit chroot and reboot
run_command "exit"
run_command "umount -l /mnt/gentoo/dev{/shm,/pts,}"
run_command "umount -R /mnt/gentoo"
run_command "reboot"
