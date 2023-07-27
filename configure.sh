#!/bin/bash

# Checking OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Configuring setup for Gentoo Linux..."
else
    echo "Unsupported operating system. This script is for Gentoo Linux only."
    exit 1
fi

# Checking if user is root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Checking Python3
python3 --version &> /dev/null
if [[ $? -ne 0 ]]; then
    echo "Python3 is not installed. Installing..."
    emerge --update --newuse dev-lang/python:3.9
else
    echo "Python3 is installed"
fi

# Checking pip3
pip3 --version &> /dev/null
if [[ $? -ne 0 ]]; then
    echo "pip3 is not installed. Installing..."
    emerge --update --newuse dev-python/pip
    python3 -m ensurepip --upgrade
else
    echo "pip3 is installed"
fi

# Updating pip
echo "Updating pip..."
pip3 install --upgrade pip

# Installing required Python packages from requirements.txt
echo "Installing necessary Python packages..."
while read package; do
    pip3 install "$package"
done < requirements.txt

# Making install_gentoo.py executable
echo "Making install_gentoo.py executable"
chmod +x install_gentoo.py
echo "install_gentoo.py is now executable."

# Running install_gentoo.py
./install_gentoo.py
