#!/bin/bash

set -e

# WireGuard Manager GitHub Repo
GITHUB_REPO="your-username/your-repo"   # <-- CHANGE THIS!

INSTALL_DIR="/usr/local/bin"
TARGET_FILE="${INSTALL_DIR}/wireguard_manager"

echo "🚀 Installing WireGuard ProPlusDeploy Manager..."

# 1. Install required packages
echo "📦 Installing dependencies..."
if [ -x "$(command -v apt)" ]; then
    sudo apt update
    sudo apt install -y wireguard-tools qrencode zip unzip curl
elif [ -x "$(command -v dnf)" ]; then
    sudo dnf install -y wireguard-tools qrencode zip unzip curl
elif [ -x "$(command -v yum)" ]; then
    sudo yum install -y wireguard-tools qrencode zip unzip curl
else
    echo "❌ Unsupported OS. Install packages manually!"
    exit 1
fi

# 2. Download WireGuard Manager directly to /usr/local/bin
echo "⬇️ Downloading WireGuard Manager..."
sudo curl -sSfLo "$TARGET_FILE" "https://raw.githubusercontent.com/nazmul-islam21/wireguard-access-manager/refs/heads/main/wireguard_manager.sh"

# 3. Set correct permissions
sudo chmod +x "$TARGET_FILE"

# 4. Success message
echo "✅ WireGuard Manager installed successfully!"
echo ""
echo "👉 Now you can run it from anywhere by typing:"
echo "wireguard_manager"
echo ""

# Finished
