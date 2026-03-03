#!/bin/bash
set -e

echo "--- Arch Linux Custom Installer ---"

# 1. ユーザー入力の取得
lsblk
echo ""
read -p "インストール先のディスクを選択してください (例: /dev/nvme0n1): " DISK
read -p "Intel CPUですか？ (y/n): " IS_INTEL
read -p "ホスト名を入力してください: " HOSTNAME
read -p "作成するユーザー名を入力してください: " USERNAME
read -s -p "${USERNAME} のパスワードを入力してください: " USER_PW
echo ""
read -s -p "Rootのパスワードを入力してください: " ROOT_PW
echo ""

# パーティション名の判定
if [[ $DISK == *"nvme"* ]] || [[ $DISK == *"mmcblk"* ]]; then
    PART_EFI="${DISK}p1"
    PART_ROOT="${DISK}p2"
else
    PART_EFI="${DISK}1"
    PART_ROOT="${DISK}2"
fi

UCODE="amd-ucode"
[[ "$IS_INTEL" == "y" ]] && UCODE="intel-ucode"

echo "--------------------------------------"
echo "DISK: $DISK (EFI: $PART_EFI, ROOT: $PART_ROOT)"
echo "USER: $USERNAME"
echo "UCODE: $UCODE"
echo "警告: $DISK のデータはすべて消去されます。"
read -p "続行しますか？ (y/N): " CONFIRM
[[ $CONFIRM != "y" ]] && exit 1

# 2. システム時計の設定
timedatectl set-ntp true

# 3. パーティション作成 (sfdisk)
echo "Creating partitions..."
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | sfdisk $DISK
  label: gpt
  , 1G, C12A7328-F81F-11D2-BA4B-00A0C93EC93B
  , , 4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709
EOF

# 4. フォーマット
echo "Formatting..."
mkfs.fat -F 32 $PART_EFI
mkfs.btrfs -L archlinux -f $PART_ROOT

# 5. Btrfs サブボリューム作成
mount $PART_ROOT /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@snapshots
umount /mnt

# 6. マウント
echo "Mounting subvolumes..."
mount -o noatime,compress=zstd,subvolume=@ $PART_ROOT /mnt
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,.snapshots,boot/efi}
mount -o noatime,compress=zstd,subvolume=@home $PART_ROOT /mnt/home
mount -o noatime,compress=zstd,subvolume=@log $PART_ROOT /mnt/var/log
mount -o noatime,compress=zstd,subvolume=@pkg $PART_ROOT /mnt/var/cache/pacman/pkg
mount -o noatime,compress=zstd,subvolume=@snapshots $PART_ROOT /mnt/.snapshots
mount $PART_EFI /mnt/boot/efi

# 7. 基本パッケージのインストール
echo "Installing base system..."
pacstrap /mnt base linux-zen linux-zen-headers linux-firmware btrfs-progs networkmanager sudo base-devel git grub efibootmgr os-prober $UCODE

# 8. fstab 生成
genfstab -U /mnt >> /mnt/etc/fstab

# 9. packages.txt のコピー
if [ -f "packages.txt" ]; then
    cp "packages.txt" /mnt/tmp/packages.txt
else
    touch /mnt/tmp/packages.txt
fi

# 10. chroot 内での設定スクリプト生成
# 変数を chroot 内に渡すために EOF をクォートせずに展開させる
cat <<EOF > /mnt/setup_chroot.sh
#!/bin/bash
set -e

# タイムゾーンとロケール
ln -sf /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i 's/^#ja_JP.UTF-8 UTF-8/ja_JP.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=ja_JP.UTF-8" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

# パスワード設定
echo "root:$ROOT_PW" | chpasswd

# 一般ユーザー作成
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$USER_PW" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel

# ネットワーク有効化
systemctl enable NetworkManager

# yay のインストール (作成した一般ユーザーで実行)
echo "Installing yay..."
sudo -u $USERNAME bash -c "
    cd /tmp
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
"

# 追加パッケージのインストール
if [ -s "/tmp/packages.txt" ]; then
    echo "Installing extra packages..."
    sudo -u $USERNAME yay -S --needed --noconfirm - < /tmp/packages.txt
fi

# GRUB 設定
echo "Configuring GRUB..."
echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

# Windows 等の OS 検知 (マウントして実行)
grub-mkconfig -o /boot/grub/grub.cfg

# Snapper 設定 (初期設定)
if pacman -Qi snapper &> /dev/null; then
    umount /.snapshots
    rm -rf /.snapshots
    snapper -c root create-config /
    mount -a
    chmod 750 /.snapshots
fi

EOF

# 11. chroot 実行
chmod +x /mnt/setup_chroot.sh
arch-chroot /mnt /setup_chroot.sh

# 後片付け
rm /mnt/setup_chroot.sh
rm /mnt/tmp/packages.txt

echo "--------------------------------------"
echo "インストールが完了しました！再起動してください。"
