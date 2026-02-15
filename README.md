# arch-setup
Arch Linuxインストール自動化スクリプト

## はじめに
手動でインストールするのめんどくさかったら`archinstall`でもいいかもしれん  
```Bash
archinstall --config "https://raw.githubusercontent.com/Kagami-omochi/arch-setup/refs/heads/main/user_configuration.json"
```
手動インストールするならはとりあえずchrootまでは手動でやらないとこのスクリプト動かんからやり方書いとく  
ファイルシステムはext4のほうがメジャーだけど今回はBtrfs使うよ


## chrootまでの手順
1. 時刻の同期


これを忘れると後の署名検証でエラーが出ることがあります。  
```Bash
timedatectl set-ntp true
```


2. ディスクパーティション作成


ディスクを確認します（例: `/dev/nvme0n1` や `/dev/sda`）
```Bash
lsblk
```
※もしインストールしたいディスクが`/dev/sda`や`/dev/sdb`等なら以下すべて`/dev/nvme0n1`を読み替える。


`fdisk` や `cfdisk` で以下の構成を作成してください。  
・EFIシステムパーティション: 512MiB〜1GiB (Type: EFI System)  
・ルートパーティション: 残り全部 (Type: Linux x86-64 root)


3. パーティションのフォーマット


作成したパーティションを初期化します。


EFIパーティション 例: `/dev/nvme0n1p1` (パーティションの1番)
```Bash
mkfs.fat -F 32 /dev/nvme0n1p1
```
ルートパーティション 例: `/dev/nvme0n1p2` (パーティションの2番)
```Bash
mkfs.btrfs -L archlinux /dev/nvme0n1p2
```
サブボリュームの構築


一度ルートにマウントして、その中に仮想的なパーティション（Subvolume）を作ります。
```Bash
mount /dev/nvme0n1p2 /mnt
```

```Bash
btrfs subvolume create /mnt/@
```

```Bash
btrfs subvolume create /mnt/@home
```

```Bash
btrfs subvolume create /mnt/@log
```

```Bash
btrfs subvolume create /mnt/@pkg
```

```Bash
umount /mnt
```


4. サブボリュームのマウント


ルートのサブボリュームをマウント
```Bash
mount -o noatime,compress=zstd,subvolume=@ /dev/nvme0n1p2 /mnt
```
必要なディレクトリを作成
```Bash
mkdir -p /mnt/{home,var/log,var/cache/pacman/pkg,boot/efi}
```
残りをマウント
```Bash
mount -o noatime,compress=zstd,subvolume=@home /dev/nvme0n1p2 /mnt/home
```
```Bash
mount -o noatime,compress=zstd,subvolume=@log /dev/nvme0n1p2 /mnt/var/log
```
```Bash
mount -o noatime,compress=zstd,subvolume=@pkg /dev/nvme0n1p2 /mnt/var/cache/pacman/pkg
```
EFIパーティションのマウント
```Bash
mount /dev/nvme0n1p1 /mnt/boot/efi
```
5. 基本システムのインストール


ベースシステムと必要なパッケージをインストールします。
```Bash
pacstrap /mnt base linux-zen linux-zen-headers linux-firmware btrfs-progs networkmanager nvim git base-devel amd-ucode
```
※Intel CPUを使ってるなら`amd-ucode`を書き換えて`intel-ucode`にする


6. fstabの生成


```Bash
genfstab -U /mnt >> /mnt/etc/fstab
```
7. ネットワークの有効化
```Bash
arch-chroot /mnt systemctl enable NetworkManager
```
8.インストールしたArch Linuxの中に入る

```Bash
arch-chroot /mnt
```


## Arch Linux本体のインストール完了！
ここまで行けたらこのリポジトリをgit cloneしてsetup.shに実行権限つけて実行してね  
あとはまかせろり
