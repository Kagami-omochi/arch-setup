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

if grep -q "GRUB_DISABLE_OS_PROBER" /etc/default/grub; then
    sudo sed -i 's/^#*GRUB_DISABLE_OS_PROBER=.*/GRUB_DISABLE_OS_PROBER=false/' /etc/default/grub
else
    echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a /etc/default/grub
fi

if [ ! -d "/.snapshots" ]; then
    snapper -c root create-config /
fi

echo "--- Configuring Dual Boot (Windows) ---"

WIN_ESP=$(lsblk -dno PATH,PARTTYPE | grep -i "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" | awk '{print $1}' | head -n 1)

if [ -n "$WIN_ESP" ]; then
    echo "Found Windows EFI partition at $WIN_ESP"
    
    MNT_TMP="/mnt/win_esp_temp"
    sudo mkdir -p "$MNT_TMP"
    
    if ! mountpoint -q "$MNT_TMP"; then
        if sudo mount -t vfat "$WIN_ESP" "$MNT_TMP" 2>/dev/null; then
            echo "Successfully mounted $WIN_ESP to $MNT_TMP"
        else
            echo "Warning: Failed to mount Windows EFI partition."
        fi
    fi

    echo "Updating GRUB config..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    if mountpoint -q "$MNT_TMP"; then
        sudo umount "$MNT_TMP"
    fi
    sudo rmdir "$MNT_TMP"
else
    echo "Windows EFI partition not found. Skipping OS Prober scan."
fi
