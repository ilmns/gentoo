#!/bin/bash

# Check for OS (assume Ubuntu, but you can add other OS checks)
if [[ "$(uname)" == "Linux" ]]; then
  echo "Configuring setup for Linux..."
else
  echo "Unsupported operating system. This script is for Linux only."
  exit 1
fi

# Install python3 and pip if they are not installed
command -v python3 &>/dev/null || {
  echo "Python 3 not found, installing..."
  sudo apt-get update
  if sudo apt-get install -y python3; then
    echo "Python 3 installed successfully."
  else
    echo "Error installing Python 3"
    exit 1
  fi
}

command -v pip3 &>/dev/null || {
  echo "pip3 not found, installing..."
  if sudo apt-get install -y python3-pip; then
    echo "pip3 installed successfully."
  else
    echo "Error installing pip3"
    exit 1
  fi
}

# Upgrade pip
python3 -m pip install --upgrade pip

# Install necessary python packages
echo "Installing necessary Python packages..."
if pip3 install -r requirements.txt; then
  echo "Python packages installed successfully."
else
  echo "Error installing Python packages. Check requirements.txt file."
  exit 1
fi

# Make the script executable
if chmod +x install_gentoo.py; then
  echo "install_gentoo.py is now executable."
else
  echo "Error making install_gentoo.py executable."
  exit 1
fi

# Execute the script
echo "Running the script..."
sudo ./install_gentoo.py
