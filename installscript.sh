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

sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/g' /etc/pacman.conf 

pacstrap /mnt base linux linux-firmware
genfstab -U /mnt >> /mnt/etc/fstab

cat << EOF > /mnt/part2.sh
#!/bin/bash

sed -i 's/#ParallelDownloads = 5/ParallelDownloads = 5/g' /etc/pacman.conf 

ln -sf /usr/share/zoneinfo/${timezone} /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

pacman -S --noconfirm base-devel sudo grub networkmanager efibootmgr
systemctl enable NetworkManager.service

echo "${hostname}" > /etc/hostname
mkinitcpio -P

useradd --create-home ${user}
usermod -aG wheel ${user}
echo "$user:$password" | chpasswd
echo "root:$password" | chpasswd

sed -i 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers

mkdir /boot/EFI
mount "${part_boot}" /boot/EFI
grub-install --target=x86_64-efi --bootloader-id=grub_uefi --recheck
grub-mkconfig -o /boot/grub/grub.cfg

pacman -Syu --noconfirm vim htop neofetch xorg xorg-xinit mesa i3 kitty dmenu unzip lxappearance nnn feh htop mpv scrot lxsession lightdm firefox pulseaudio pulseaudio-bluetooth pulseaudio-alsa picom networkmanager network-manager-applet udiskie bluez blueman dunst unclutter xfce4-power-manager lightdm-gtk-greeter
systemctl enable lightdm
systemctl enable bluetooth
mkdir -p /home/${user}/.config/i3
curl https://raw.githubusercontent.com/nalinwadhwa02/dotfiles/main/i3/config >> /home/${user}/.config/i3/config
curl https://raw.githubusercontent.com/nalinwadhwa02/dotfiles/main/autostart.sh >> /home/${user}/.config/autostart.sh
chmod 700 /home/${user}/.config/autostart.sh

exit
EOF

chmod 700 /mnt/part2.sh
arch-chroot /mnt ./part2.sh

