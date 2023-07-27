#!/usr/bin/env python3

import os
import sys
import requests
import argparse
import subprocess
import crypt
import re
from getpass import getpass
from bs4 import BeautifulSoup

def parse_args():
    parser = argparse.ArgumentParser(description='Automated Gentoo Linux installation script.')
    parser.add_argument('--help', action='help', default=argparse.SUPPRESS,
                        help='Show this help message and exit')
    return parser.parse_args()

def notify_step(step):
    print("\n" + "=" * 40)
    print(f"STEP: {step}")
    print("=" * 40)

def check_root():
    notify_step("Checking if the script is running as root")
    if os.geteuid() != 0:
        sys.exit("This script must be run as root")

def check_network():
    notify_step("Checking the network connection")
    try:
        requests.get("http://www.google.com", timeout=5)
        print("Internet connection is working")
    except requests.ConnectionError:
        sys.exit("No internet connection. Please check and try again.")

def fetch_latest_url():
    notify_step("Fetching the latest stage3 tarball URL")
    try:
        response = requests.get("http://distfiles.gentoo.org/releases/amd64/autobuilds/current-stage3-amd64/")
        soup = BeautifulSoup(response.text, 'html.parser')
        for link in soup.find_all('a'):
            href = link.get('href')
            if "stage3-amd64" in href:
                return f"{url}{href}"
    except requests.exceptions.RequestException as err:
        sys.exit(f"Error fetching latest URL: {err}")
    sys.exit("Unable to find latest stage3 tarball URL")

def run_command(command, exit_on_fail=True):
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
        if exit_on_fail:
            sys.exit(1)

def list_disks():
    notify_step("Listing available disks")
    disks = subprocess.check_output("lsblk -dpno NAME,SIZE", shell=True, text=True).split("\n")
    for i, disk in enumerate(disks, start=1):
        print(f"{i}. {disk}")
    return disks

def partition_disks():
    notify_step("Partitioning the selected disk")
    disks = list_disks()
    while True:
        try:
            disk_num = int(input("Please enter the number of the disk to install Gentoo on: "))
            disk_name = disks[disk_num-1].split()[0]
            break
        except ValueError:
            print("Invalid input. Please enter a number.")
    commands = [
        f"parted -s {disk_name} mklabel gpt",
        f"parted -s {disk_name} mkpart primary ext4 1MiB 100%",
        f"mkfs.ext4 {disk_name}1",
        f"mount {disk_name}1 /mnt/gentoo"
    ]
    for cmd in commands:
        run_command(cmd)

def download_extract_stage3():
    notify_step("Downloading and extracting stage3 tarball")
    url = fetch_latest_url()
    output_file = "/mnt/gentoo/stage3-amd64-latest.tar.xz"
    run_command(f"wget {url} -O {output_file}")
    run_command(f"tar xpvf {output_file} -C /mnt/gentoo --xattrs")

def copy_dns_info():
    notify_step("Copying DNS info")
    run_command("cp --dereference /etc/resolv.conf /mnt/gentoo/etc/")

def mount_filesystems():
    notify_step("Mounting necessary filesystems")
    mount_commands = [
        "mount --types proc /proc /mnt/gentoo/proc",
        "mount --rbind /sys /mnt/gentoo/sys",
        "mount --make-rslave /mnt/gentoo/sys",
        "mount --rbind /dev /mnt/gentoo/dev",
        "mount --make-rslave /mnt/gentoo/dev"
    ]
    for cmd in mount_commands:
        run_command(cmd)

def configure_portage():
    notify_step("Configuring Portage")
    commands = ["emerge-webrsync", "emerge --sync"]
    for cmd in commands:
        run_command(cmd)

def install_packages(packages):
    for pkg in packages:
        notify_step(f"Installing package {pkg}")
        run_command(f"emerge {pkg}")

def configure_kernel():
    notify_step("Configuring the Linux kernel")
    commands = ["emerge sys-kernel/genkernel", "genkernel all"]
    for cmd in commands:
        run_command(cmd)

def check_password_strength(password):
    """ Checks that the password contains at least eight characters, one uppercase letter, one lowercase letter, and one number. """
    pattern = re.compile("^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[a-zA-Z\d]{8,}$")
    return bool(pattern.match(password))

def configure_system(hostname, username):
    notify_step("Configuring system with user provided details")
    root_password = get_secure_password("root")
    user_password = get_secure_password(username)

    encrypted_root_password = crypt.crypt(root_password)
    encrypted_user_password = crypt.crypt(user_password)

    commands = [
        f"echo '{hostname}' > /etc/hostname",
        f"echo root:{encrypted_root_password} | chpasswd -e",
        f"useradd -m -G users,wheel,audio -s /bin/bash {username}",
        f"echo {username}:{encrypted_user_password} | chpasswd -e"
    ]
    for cmd in commands:
        run_command(cmd)

def get_secure_password(user):
    while True:
        password = getpass(f"Please enter the password for {user}: ")
        if check_password_strength(password):
            return password
        print("Password must contain at least eight characters, one uppercase letter, one lowercase letter, and one number.")

def main():
    args = parse_args()
    try:
        check_root()
        check_network()
        partition_disks()
        download_extract_stage3()
        copy_dns_info()
        mount_filesystems()
        configure_portage()
        packages = ["sys-kernel/linux-firmware", "net-misc/dhcpcd", "sys-boot/grub", "x11-base/xorg-drivers", "x11-base/xorg-server",
                    "x11-wm/bspwm", "x11-terms/rxvt-unicode", "www-client/firefox", "app-editors/vim", "media-gfx/feh", "media-sound/alsa-utils"]
        install_packages(packages)
        configure_kernel()
        configure_system("gentoo", "user")
    except Exception as e:
        print(f"An error occurred: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()
