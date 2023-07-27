#!/bin/bash

# Check for OS (assume Gentoo)
if [[ "$(uname)" == "Linux" ]]; then
  echo "Configuring setup for Gentoo Linux..."
else
  echo "Unsupported operating system. This script is for Gentoo Linux only."
  exit 1
fi

# Check if user is root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Install python3 if it's not installed
command -v python3 &>/dev/null || {
  echo "Python 3 not found, installing..."
  emerge --update --newuse dev-lang/python:3.9
}

# Check python version
python_version=$(python3 -c 'import sys; print(sys.version_info.major)')
if [[ $python_version -eq 3 ]]; then
  echo "Python 3 is installed"
else
  echo "Python 3 is not installed"
  exit 1
fi

# Install pip for Python3 if it's not installed
command -v pip3 &>/dev/null || {
  echo "pip3 not found, installing..."
  emerge --update --newuse dev-python/pip
  python3 -m ensurepip --upgrade
}

# Check pip version
pip_version=$(pip3 -V | awk '{print $2}')
if [[ $pip_version == *"pip"* ]]; then
  echo "pip is installed"
else
  echo "pip is not installed"
  exit 1
fi

# Update pip
echo "Updating pip..."
pip3 install --upgrade pip

# Install the necessary python packages
echo "Installing necessary Python packages..."
pip3 install -r requirements.txt

# Make the script executable
chmod +x install_gentoo.py
echo "install_gentoo.py is now executable."

# Execute the script
./install_gentoo.py
