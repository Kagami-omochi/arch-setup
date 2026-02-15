#!/bin/bash
set -e

PKG_LIST="packages.txt"

echo "--- Arch Linux Unified Setup ---"

sudo pacman -S --needed --noconfirm base-devel git

if ! command -v yay &> /dev/null; then
    echo "Installing yay..."
    _temp_dir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$_temp_dir"
    cd "$_temp_dir" && makepkg -si --noconfirm
    cd - && rm -rf "$_temp_dir"
fi

if [ -f "$PKG_LIST" ]; then
    echo "Installing packages from packages.txt..."
    sed -e 's/#.*//' -e '/^$/d' "$PKG_LIST" | xargs -ro yay -S --needed --noconfirm
else
    echo "Error: $PKG_LIST not found."
    exit 1
fi

echo "--- The package installation is complete! ---"

if [ ! -d "/.snapshots" ]; then
    snapper -c root create-config /
fi
