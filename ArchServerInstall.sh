#!/bin/bash
# WARNING: this script will destroy data on the selected disk.
# This script can be run by executing the following:
#   curl -sL https://git.io/vNxbN | bash
set -uo pipefail
#Repo URL 
REPO_URL="http://mirrors.aggregate.org/archlinux/archlinux/community-staging/os/x86_64/"
echo wping disk

 curl -sL https://git.io/vNxbN | bash 
 
### Get infomation from user ###
hostname=$(dialog --stdout --inputbox "Enter hostname" 0 0) || exit 1
clear
: ${hostname:?"hostname cannot be empty"}

user=$(dialog --stdout --inputbox "Enter admin username" 0 0) || exit 1
clear
: ${user:?"user cannot be empty"}

password=$(dialog --stdout --passwordbox "Enter admin password" 0 0) || exit 1
clear
: ${password:?"password cannot be empty"}
password2=$(dialog --stdout --passwordbox "Enter admin password again" 0 0) || exit 1
clear
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )

devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
device=$(dialog --stdout --menu "Select installation disk" 0 0 0 ${devicelist}) || exit 1
clear

### Set up logging ###
exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

timedatectl set-ntp true
hwclock --systohc --utc


### Setup the disk and partitions ###
swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
swap_end=$(( $swap_size + 129 + 1 ))MiB

parted --script "${device}" -- mklabel gpt \
  mkpart ESP fat32 1Mib 129MiB \
  set 1 boot on \
  mkpart primary linux-swap 2129MiB ${swap_end} \
  mkpart primary ext4 ${swap_end} 100%

# Simple globbing was not enough as on one device I needed to match /dev/mmcblk0p1
# but not /dev/mmcblk0boot1 while being able to match /dev/sda1 on other devices.
part_boot="$(ls ${device}* | grep -E "^${device}p?1$")"
part_swap="$(ls ${device}* | grep -E "^${device}p?2$")"
part_root="$(ls ${device}* | grep -E "^${device}p?3$")"

wipefs "${part_boot}"
wipefs "${part_swap}"
wipefs "${part_root}"

mkfs.vfat -F32 "${part_boot}"
mkswap "${part_swap}"
mkfs.f2fs -f "${part_root}"

swapon "${part_swap}"
mount "${part_root}" /mnt
mkdir /mnt/boot
mount "${part_boot}" /mnt/boot 

### Install and configure the basic system ###
cat >>/etc/pacman.conf <<EOF
[mdaffin]
SigLevel = Optional TrustAll
Server = $REPO_URL
EOF

pacstrap /mnt base linux linux-firmware
genfstab -t PARTUUID /mnt >> /mnt/etc/fstab
echo "${hostname}" > /mnt/etc/hostname

cat >>/mnt/etc/pacman.conf <<EOF
[mdaffin]
SigLevel = Optional TrustAll
Server = $REPO_URL
EOF
arch-chroot /mnt git install
arch-chroot /mnt zsh install  
arch-chroot /mnt openssh install
arch-chroot /mnt jre-openjdk install  
arch-chroot /mnt neofetch install
arch-chroot /mnt grub os-prober install


echo "LANG=en_GB.UTF-8" > /mnt/etc/locale.conf

arch-chroot /mnt useradd -mU -s /usr/bin/zsh -G wheel,uucp,video,audio,storage,games,input "$user"
arch-chroot /mnt chsh -s /usr/bin/zsh

echo "$user:$password" | chpasswd --root /mnt
echo "root:$password" | chpasswd --root /mnt

echo "neofetch" > /mnt/home/"$user"/.bashrc
echo "neofetch" > /mnt/home/"root"/.bashrc

arch-chroot /mnt  git clone https://github.com/bhilburn/powerlevel9k.git /home/"$user"/.oh-my-zsh/custom/themes/powerlevel9k
arch-chroot /mnt  git clone https://github.com/bhilburn/powerlevel9k.git /home/"root"/.oh-my-zsh/custom/themes/powerlevel9k

arch-chroot /mnt systemctl enable sshd.service

arch-chroot /mnt grub-install --recheck /dev/sda 

arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg


exit

umount -R /mnt

reboot

