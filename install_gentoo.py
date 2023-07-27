#!/usr/bin/env python3

import os
import sys
import requests
import argparse
import subprocess
import hashlib
import binascii
import re
from getpass import getpass
from bs4 import BeautifulSoup

def parse_arguments():
    parser = argparse.ArgumentParser(description='Automated Gentoo Linux installation script.')
    parser.add_argument('--help', action='help', default=argparse.SUPPRESS,
                        help='Show this help message and exit')
    return parser.parse_args()

def display_step(step):
    print("\n" + "=" * 40)
    print(f"STEP: {step}")
    print("=" * 40)

def verify_root_user():
    display_step("Verifying root user access")
    if os.geteuid() != 0:
        sys.exit("This script must be run as root")

def verify_network_connection():
    display_step("Verifying network connectivity")
    try:
        requests.get("http://www.google.com", timeout=5)
        print("Network connection is functional")
    except requests.ConnectionError:
        sys.exit("No network connection. Please check and retry.")

def get_latest_stage3_url():
    display_step("Fetching the latest stage3 tarball URL")
    try:
        response = requests.get("http://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64/")
        soup = BeautifulSoup(response.text, 'html.parser')
        for link in soup.find_all('a'):
            href = link.get('href')
            if "stage3-amd64" in href:
                return f"http://distfiles.gentoo.org/releases/amd64/autobuilds/{href}"
    except requests.exceptions.RequestException as err:
        sys.exit(f"Error in fetching latest URL: {err}")
    sys.exit("Unable to find latest stage3 tarball URL")

def execute_command(command, exit_on_error=True):
    try:
        process = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        print(f"\nCommand Execution Successful!")
        print(f"Command: {command}")
        print(f"Output: {process.stdout.decode()}")
    except subprocess.CalledProcessError as e:
        print(f"\nCommand Execution Failed!")
        print(f"Command: {command}")
        print(f"Error Code: {e.returncode}")
        print(f"Error Message: {e.stderr.decode()}")
        if exit_on_error:
            sys.exit(1)

def show_available_disks():
    display_step("Listing available disks")
    disks = subprocess.check_output("lsblk -dpno NAME,SIZE", shell=True, text=True).split("\n")
    for i, disk in enumerate(disks, start=1):
        print(f"{i}. {disk}")
    return disks

def create_partitions():
    display_step("Partitioning the selected disk")
    disks = show_available_disks()
    while True:
        try:
            disk_num = int(input("Please enter the disk number for Gentoo installation: "))
            disk_name = disks[disk_num-1].split()[0]
            break
        except (ValueError, IndexError):
            print("Invalid input. Please enter a valid number.")
    commands = [
        f"parted -s {disk_name} mklabel gpt",
        f"parted -s {disk_name} mkpart primary ext4 1MiB 100%",
        f"mkfs.ext4 {disk_name}1",
        f"mount {disk_name}1 /mnt/gentoo"
    ]
    for cmd in commands:
        execute_command(cmd)

def download_and_extract_stage3():
    display_step("Downloading and extracting stage3 tarball")
    url = get_latest_stage3_url()
    output_file = "/mnt/gentoo/stage3-amd64-latest.tar.xz"
    execute_command(f"wget {url} -O {output_file}")
    execute_command(f"tar xpvf {output_file} -C /mnt/gentoo --xattrs")

def copy_dns_info():
    display_step("Copying DNS info")
    execute_command("cp --dereference /etc/resolv.conf /mnt/gentoo/etc/")

def mount_necessary_filesystems():
    display_step("Mounting necessary filesystems")
    mount_commands = [
        "mount --types proc /proc /mnt/gentoo/proc",
        "mount --rbind /sys /mnt/gentoo/sys",
        "mount --make-rslave /mnt/gentoo/sys",
        "mount --rbind /dev /mnt/gentoo/dev",
        "mount --make-rslave /mnt/gentoo/dev"
    ]
    for cmd in mount_commands:
        execute_command(cmd)

def setup_portage():
    display_step("Setting up Portage")
    commands = ["emerge-webrsync", "emerge --sync"]
    for cmd in commands:
        execute_command(cmd)

def install_package_list(packages):
    for pkg in packages:
        display_step(f"Installing package {pkg}")
        execute_command(f"emerge {pkg}")

def configure_kernel():
    display_step("Configuring the Linux kernel")
    commands = ["emerge sys-kernel/genkernel", "genkernel all"]
    for cmd in commands:
        execute_command(cmd)

def validate_password_strength(password):
    """ Validate the password strength. """
    pattern = re.compile("^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[a-zA-Z\d]{8,}$")
    return bool(pattern.match(password))

def create_password_hash(password):
    """Create a password hash."""
    salt = hashlib.sha256(os.urandom(60)).hexdigest().encode('ascii')
    pwdhash = hashlib.pbkdf2_hmac('sha512', password.encode('utf-8'), 
                                salt, 100000)
    pwdhash = binascii.hexlify(pwdhash)
    return (salt + pwdhash).decode('ascii')

def setup_system(hostname, username):
    display_step("Setting up system with user details")
    root_password = get_secure_password("root")
    user_password = get_secure_password(username)

    hashed_root_password = create_password_hash(root_password)
    hashed_user_password = create_password_hash(user_password)

    commands = [
        f"echo '{hostname}' > /etc/hostname",
        f"echo root:{hashed_root_password} | chpasswd -e",
        f"useradd -m -G users,wheel,audio -s /bin/bash {username}",
        f"echo {username}:{hashed_user_password} | chpasswd -e"
    ]
    for cmd in commands:
        execute_command(cmd)

def get_secure_password(user):
    while True:
        password = getpass(f"Enter password for {user}: ")
        if validate_password_strength(password):
            return password
        print("Password must contain at least eight characters, one uppercase letter, one lowercase letter, and one number. Please try again.")

def main():
    args = parse_arguments()
    verify_root_user()
    verify_network_connection()

    create_partitions()
    download_and_extract_stage3()
    copy_dns_info()
    mount_necessary_filesystems()
    chroot_commands = [
        setup_portage,
        lambda: install_package_list(["sys-apps/baselayout", "sys-process/systemd"]),
        configure_kernel,
        lambda: setup_system("gentoo", "user1"),
    ]
    for cmd in chroot_commands:
        execute_command(f"chroot /mnt/gentoo /bin/bash -c '{cmd}'", exit_on_error=False)
    execute_command("umount -l /mnt/gentoo/dev{/shm,/pts,}", exit_on_error=False)
    execute_command("umount -R /mnt/gentoo", exit_on_error=False)
    print("\nGentoo Linux has been installed successfully!")

if __name__ == "__main__":
    main()
