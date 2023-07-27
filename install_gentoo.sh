#!/bin/bash

# Function to display status messages in blue
print_status() {
  echo -e "\033[34m$1\033[0m"
}

# Function to display error messages in red and exit
print_error_and_exit() {
  echo -e "\033[31mError: $1\033[0m" >&2
  exit 1
}

# Function to prompt for a yes/no confirmation
prompt_yes_no() {
  read -r -p "$1 [Y/n]: " response
  case "$response" in
    [nN][oO]|[nN])
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

print_status "Welcome to the Gentoo Linux installation script!"

# Prompt for the target NVMe drive for installation
read -rp "Enter the target NVMe drive for installation (e.g., /dev/nvme0n1): " TARGET_DRIVE
[[ -b "$TARGET_DRIVE" ]] || print_error_and_exit "Invalid drive: $TARGET_DRIVE"

# Prompt for the EFI partition mount point
read -rp "Enter the EFI partition mount point (e.g., /mnt/gentoo/boot/efi): " EFI_MOUNT
if [[ ! -d "$EFI_MOUNT" ]]; then
  print_error_and_exit "Invalid mount point: $EFI_MOUNT"
fi

# Prompt for the hostname for the system
read -rp "Enter the hostname for the system: " HOSTNAME

# Prompt for the timezone
read -rp "Enter the timezone (e.g., Europe/Helsinki): " TIMEZONE

# Prompt for the root password
while true; do
  read -rsp "Enter the root password: " ROOT_PASSWORD
  echo
  read -rsp "Confirm the root password: " ROOT_PASSWORD_CONFIRM
  echo
  [[ "$ROOT_PASSWORD" = "$ROOT_PASSWORD_CONFIRM" ]] && break
  print_status "Passwords do not match. Please try again."
done

# Prompt for USE flags (comma-separated)
read -rp "Enter USE flags (comma-separated, or press Enter for default): " USE_FLAGS

# Confirmation before starting the installation
prompt_yes_no "Are you sure you want to proceed with the installation?" || exit 0

set -e


print_status "Step 1: Partitioning the NVMe drive"

# Check if the NVMe drive is already mounted or in use
if mount | grep -q "$TARGET_DRIVE"; then
  print_error_and_exit "The target NVMe drive is already mounted. Please unmount it and try again."
fi

# Unmount partitions, if any
if mount | grep -q "${TARGET_DRIVE}p"; then
  umount "${TARGET_DRIVE}p"* || print_error_and_exit "Failed to unmount partitions."
fi

# Partition the NVMe drive if it's not already partitioned with GPT
if ! parted -s "$TARGET_DRIVE" print | grep -q 'gpt'; then
  parted -s "$TARGET_DRIVE" mklabel gpt || print_error_and_exit "Failed to create GPT partition table."
  parted -s "$TARGET_DRIVE" mkpart primary fat32 1MiB 512MiB || print_error_and_exit "Failed to create EFI partition."
  parted -s "$TARGET_DRIVE" set 1 esp on || print_error_and_exit "Failed to set ESP flag on EFI partition."
  parted -s "$TARGET_DRIVE" mkpart primary ext4 512MiB 100% || print_error_and_exit "Failed to create root partition."
  sleep 1  # Wait for the partition changes to take effect
else
  print_status "The target NVMe drive is already partitioned with GPT."
fi

# Update partition table outside the chroot environment
partprobe "$TARGET_DRIVE" || print_error_and_exit "Failed to update partition table."

print_status "Step 2: Formatting partitions"
# Format the partitions
mkfs.fat -F 32 "${TARGET_DRIVE}p1" || print_error_and_exit "Failed to format EFI partition."
mkfs.ext4 "${TARGET_DRIVE}p2" || print_error_and_exit "Failed to format root partition."

print_status "Step 3: Mounting the partitions"
# Mount the partitions
mount "${TARGET_DRIVE}p2" /mnt/gentoo || print_error_and_exit "Failed to mount root partition."
mkdir -p "$EFI_MOUNT" || print_error_and_exit "Failed to create EFI mount point."
mount "${TARGET_DRIVE}p1" "$EFI_MOUNT" || print_error_and_exit "Failed to mount EFI partition."


print_status "Step 4: Setting the date"
# Set the date
ntpd -q -g

print_status "Step 5: Downloading the Gentoo stage3 tarball"
# Download the Gentoo stage3 tarball
STAGE3_URL="http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64.txt"
STAGE3_FILE=$(wget -qO- "$STAGE3_URL" | grep -Eo 'stage3-amd64-.*\.tar\.xz' | tail -n 1)
STAGE3_URL="http://distfiles.gentoo.org/releases/amd64/autobuilds/$STAGE3_FILE"
wget "$STAGE3_URL" -O "/mnt/gentoo/$STAGE3_FILE"
tar xvf "/mnt/gentoo/$STAGE3_FILE" -C /mnt/gentoo --xattrs-include='*.*' --numeric-owner
rm "/mnt/gentoo/$STAGE3_FILE"

print_status "Step 6: Configuring the Gentoo installation"
# Configure the Gentoo installation
mirrorselect -i -o >> /mnt/gentoo/etc/portage/make.conf
mkdir -p /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
cp -L /etc/resolv.conf /mnt/gentoo/etc/

# Optional: Configure USE flags
if [[ -n "$USE_FLAGS" ]]; then
  echo "USE=\"$USE_FLAGS\"" >> /mnt/gentoo/etc/portage/make.conf
fi

print_status "Step 7: Mounting necessary filesystems"
# Mount necessary filesystems
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/dev

print_status "Step 8: Entering the chroot environment"
# Entering the chroot environment
chroot /mnt/gentoo /bin/bash <<EOF
source /etc/profile
export PS1="(chroot) \$PS1"

print_status "Step 9: Setting the timezone"
# Set the timezone
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "$TIMEZONE" > /etc/timezone

print_status "Step 10: Setting the system clock"
# Set the system clock
hwclock --systohc

print_status "Step 11: Configuring the locale"
# Configure the locale
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8

print_status "Step 12: Setting the hostname"
# Set the hostname
echo "hostname=\"$HOSTNAME\"" > /etc/conf.d/hostname

print_status "Step 13: Setting the root password"
# Set the root password
echo "root:$ROOT_PASSWORD" | chpasswd

print_status "Step 14: Installing the Gentoo base system"
# Install the Gentoo base system
emerge-webrsync
emerge --sync
emerge --oneshot sys-apps/portage
emerge --update --deep --newuse @world

print_status "Step 15: Configuring the bootloader (GRUB)"
# Configure the bootloader (GRUB)
emerge sys-boot/grub:2
grub-install --target=x86_64-efi --efi-directory="$EFI_MOUNT" --bootloader-id=Gentoo
grub-mkconfig -o /boot/grub/grub.cfg

print_status "Step 16: Enabling necessary services"
# Enable necessary services
rc-update add sshd default
rc-update add dhcpcd default

EOF

print_status "Step 17: Generating fstab"
# Generate fstab
genfstab -U /mnt/gentoo >> /mnt/gentoo/etc/fstab

print_status "Step 18: Exiting the chroot environment"
# Exiting the chroot environment
umount -l /mnt/gentoo/dev{/shm,/pts,}
umount /mnt/gentoo{/boot/efi,/proc,/sys,}
umount /mnt/gentoo

print_status "Installation completed successfully. You can now reboot your system."
