#!/bin/bash

exec 1> >(tee "stdout.log")
exec 2> >(tee "stderr.log")

echo -n "Hostname: "
read hostname
: ${hostname:?"Missing hostname"}
echo
echo -n "User: "
read user 
: ${hostname:?"Missing user"}
echo
echo -n "Password: "
read -s password
echo
echo -n "Repeat Password: "
read -s password2
echo
[[ "$password" == "$password2" ]] || ( echo "Passwords did not match"; exit 1; )
echo
devicelist=$(lsblk -dplnx size -o name,size | grep -Ev "boot|rpmb|loop" | tac)
echo -n "devices: " 
echo
echo -n "${devicelist}" 
echo
echo -n "Enter device to use: "
read device
echo
echo -n "Enter timezone: "
read timezone
echo
: ${timezone:?"timezone needs to be Region/City"}
clear

timedatectl set-ntp true

swap_size=$(free --mebi | awk '/Mem:/ {print $2}')
swap_end=$(( $swap_size + 129 + 1 ))MiB

parted --script "${device}" -- mklabel gpt \
  mkpart ESP fat32 1Mib 129MiB \
  set 1 boot on \
  mkpart primary linux-swap 129MiB ${swap_end} \
  mkpart primary ext4 ${swap_end} 100%


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

pacstrap /mnt base linux linux-firmware
genfstab -U /mnt >> /mnt/etc/fstab

cat << EOF > /mnt/part2.sh
#!/bin/bash

ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime
hwclock --systohc


echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

pacman -S --noconfirm base-devel sudo grub networkmanager
systemctl enable NetworkManager.service

echo "${hostname}" > /etc/hostname
mkinitcpio -P

useradd -mU -s /usr/bin/bash -G wheel,uucp,video,audio,storage,games,input "$user"
echo "$user:$password" | chpasswd
echo "root:$password" | chpasswd
sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

grub-install --recheck ${part_root}
grub-mkconfig -o /boot/grub/grub.cfg

pacman -Syu --noconfirm vim htop neofetch

exit
EOF

chmod 700 /mnt/part2.sh
arch-chroot /mnt ./part2.sh

