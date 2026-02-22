#!/bin/bash
set -e

echo "--- Arch Linux Auto Installer ---"

lsblk
echo ""
read -p "Please select the disk for installation (e.g., /dev/nvme0n1): " DISK
read -p "If you are using an Intel CPU, enter 'y' if you are using an AMD CPU, enter 'n'." IS_INTEL

if [[ $DISK == *"nvme"* ]]; then
    PART_EFI="${DISK}p1"
    PART_ROOT="${DISK}p2"
else
    PART_EFI="${DISK}1"
    PART_ROOT="${DISK}2"
fi

UCODE="amd-ucode"
if [ "$IS_INTEL" = "y" ]; then
    UCODE="intel-ucode"
fi

echo "--------------------------------------"
echo "DISK: $DISK (EFI: $PART_EFI, ROOT: $PART_ROOT)"
echo "UCODE: $UCODE"
echo "Warning: All data on $DISK will be erased."
read -p "Continue? (y/N): " CONFIRM
[[ $CONFIRM != "y" ]] && exit 1

echo "Synchronizing time..."
timedatectl set-ntp true

echo "Creating partition..."
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | sfdisk $DISK
  label: gpt
  , 1G, C12A7328-F81F-11D2-BA4B-00A0C93EC93B
  , , 4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
EOF

echo "Formatting..."
mkfs.fat -F 32 $PART_EFI
mkfs.btrfs -L archlinux -f $PART_ROOT

mount $PART_ROOT /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
umount /mnt

echo "Mounting subvolume..."
mount -o noatime,compress=zstd,subvolume=@ $PART_ROOT /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,boot/efi}
mount -o noatime,compress=zstd,subvolume=@home $PART_ROOT /mnt/home
mount -o noatime,compress=zstd,subvolume=@log $PART_ROOT /mnt/var/log
mount -o noatime,compress=zstd,subvolume=@pkg $PART_ROOT /mnt/var/cache/pacman/pkg
mount $PART_EFI /mnt/boot/efi

echo "Installing package..."
pacstrap /mnt base linux-zen linux-zen-headers linux-firmware btrfs-progs networkmanager $UCODE

genfstab -U /mnt >> /mnt/etc/fstab

echo "--------------------------------------"
echo "The basic installation is complete."

arch-chroot /mnt

systemctl enable NetworkManager

ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc

sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=ja_JP.UTF-8" > /etc/locale.conf

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
