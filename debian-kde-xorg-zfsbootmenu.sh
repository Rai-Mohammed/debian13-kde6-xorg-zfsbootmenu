#!/bin/bash

# Bash script to install Debian 13, KDE Plasma 6, xserver-xorg with ZFS on Root and ZFSBootMenu

# Automatically set other variables
PHY_DRIVE="/dev/sda"

# First, define variables that refer to the disk and partition number that will hold boot files:
# Single SATA disk :
BOOT_DISK=$PHY_DRIVE
BOOT_PART="1"
BOOT_DEVICE="${BOOT_DISK}${BOOT_PART}"

# Second, define variables that refer to the disk and partition number that will hold swap files:
# Single SATA disk :
SWAP_DISK=$PHY_DRIVE
SWAP_PART="2"
SWAP_DEVICE="${SWAP_DISK}${SWAP_PART}"

# Next, define variables that refer to the disk and partition number that will hold the ZFS pool:
# Single SATA disk :
POOL_DISK=$PHY_DRIVE
POOL_PART="3"
POOL_DEVICE="${POOL_DISK}${POOL_PART}"

ZPOOL_NAME="zroot"
ZBM_EFI_PATH="https://get.zfsbootmenu.org/efi"

KERNEL_VERSION=$(uname -r)  # Automatically get current kernel version
MOUNT_POINT="/mnt"
OS_ID=$(source /etc/os-release && echo "$ID")  # Get OS ID from /etc/os-release
OS_DISTRIBUTION="trixie"
APT_MIRROR="http://archive.debian.com/debian/"
CPU_ARCH="intel"
USERNAME="fill_your_username"
USER_PASSWORD="fill_your_user_password"
ROOT_PASSWORD="fill_your_root_password"
HOSTNAME="fill_your_hostname"

IF_PHY_DNS="1.1.1.1,8.8.8.8,9.9.9.9,8.8.4.4"

IF_PHY_NET="enp0s3"
IF_PHY_ADDRESS_NET="10.0.2.228"
IF_PHY_NETMASK_NET="24"
IF_PHY_GATEWAY_NET="10.0.2.2"

IF_PHY_HOA="enp0s8"
IF_PHY_ADDRESS_HOA="192.168.59.228"
IF_PHY_NETMASK_HOA="24"
IF_PHY_GATEWAY_HOA="192.168.59.1"
#----------------------------------
# From : https://docs.zfsbootmenu.org/en/latest/guides/ubuntu/uefi.html#

# Install helpers
apt install -y debootstrap parted gdisk shim-signed mokutil dkms zfs-dkms zfsutils-linux

# Generate /etc/hostid
zgenhostid -f

# Define disk variables
# Verify your target disk devices with lsblk
lsblk

# Disk preparation
parted "$PHY_DRIVE" mklabel gpt

# Wipe partitions
zpool destroy -f $ZPOOL_NAME
zpool clear -F $ZPOOL_NAME
zpool labelclear -f $POOL_DEVICE

wipefs -a "$PHY_DRIVE"

sgdisk --zap-all "$PHY_DRIVE"

# Create EFI boot partition
sgdisk -n "${BOOT_PART}:1m:+512m" -t "${BOOT_PART}:ef00" -c "${BOOT_PART}:EFI System Partition" "$BOOT_DISK"

# Create SWAP partition
sgdisk -n "${SWAP_PART}:0:+12G" -t "${SWAP_PART}:8200" -c "${SWAP_PART}:Linux Ubuntu SWAP" "$SWAP_DISK"

# Create zpool partition
sgdisk -n "${POOL_PART}:0:-10m" -t "${POOL_PART}:bf00" -c "${POOL_PART}:Ubuntu ZFS zroot Partition" "$POOL_DISK"

# Verify your target disk devices with lsblk
lsblk

# ZFS verification
zpool status

# ZFS pool creation
# Remarques
  #  -o (Lowercase): Sets Pool properties. These affect the entire storage group (e.g., ashift for disk alignment or autotrim for SSD health).
  #  -O (Uppercase): Sets Dataset properties. These affect how data is written to the root file system (e.g., compression or acltype).

zpool create -f -o ashift=12 \
 -o autotrim=on \
 -O compression=zstd \
 -O acltype=posixacl \
 -O xattr=sa \
 -O relatime=on \
 -m none "$ZPOOL_NAME" "$POOL_DEVICE"

zpool status
# Create initial file systems

 zfs create -o mountpoint=none $ZPOOL_NAME/ROOT

 zfs create -o mountpoint=/ -o canmount=noauto $ZPOOL_NAME/ROOT/$OS_ID

 zfs create -o mountpoint=/home $ZPOOL_NAME/home

 zfs create -o mountpoint=/home/$USERNAME $ZPOOL_NAME/home/$USERNAME

 zpool set bootfs=$ZPOOL_NAME/ROOT/$OS_ID $ZPOOL_NAME

# Export, then re-import with a temporary mountpoint of $MOUNT_POINT

 zpool export $ZPOOL_NAME
 zpool import -N -R $MOUNT_POINT $ZPOOL_NAME
 zfs mount $ZPOOL_NAME/ROOT/$OS_ID
 zfs mount $ZPOOL_NAME/home
 zfs mount $ZPOOL_NAME/home/$USERNAME

# Verify that everything is mounted correctly
mount | grep mnt

# Update device symlinks
 udevadm trigger

# Install Debian
 debootstrap $OS_DISTRIBUTION $MOUNT_POINT

# Copy files into the new install

cp /etc/hostid $MOUNT_POINT/etc
cp /etc/resolv.conf $MOUNT_POINT/etc

# Chroot into the new OS

mount -t proc proc $MOUNT_POINT/proc
mount -t sysfs sys $MOUNT_POINT/sys
mount -B /dev $MOUNT_POINT/dev
mount -t devpts pts $MOUNT_POINT/dev/pts

chroot $MOUNT_POINT /bin/bash <<EOF_CHROOT
# Basic Ubuntu Configuration
# Set a hostname

echo "$HOSTNAME" > /etc/hostname
echo -e "127.0.1.1\t $HOSTNAME" >> /etc/hosts

cat /etc/hosts

# Set a root password
echo "Setting root password..."
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user and set password
echo "Creating user and setting permissions..."
useradd $USERNAME --shell /bin/bash --home /home/$USERNAME 
usermod -aG sudo,audio,cdrom,dip,floppy,plugdev,operator,netdev,video,render $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Check if the directory exists and confirm the user''s settings.

# Check if the directory /home/$USERNAME exists.
# You can also use the id command to see if the user exists and what their home directory is set to.
# Check the /etc/passwd file to see the actual home directory specified for the user.
cat /etc/passwd | grep $USERNAME

# Set correct ownership and permissions.
# The home directory must be owned by the user.
chown -R $USERNAME:$USERNAME /home/$USERNAME

# The user needs permission to enter the directory. The 755 permission is a good default, which allows the owner to read, write, and execute, and others to read and execute.
#  chmod 755 /home/$USERNAME

# Copy default shell files (if necessary).
# If you created the directory manually, you may need to copy default shell configuration files.
cp -r /etc/skel/. /home/$USERNAME/
chown -R $USERNAME:$USERNAME /home/$USERNAME/

#For a more automated and robust solution, use mkhomedir_helper if available


# Configure apt sources inside Chroot

    cat  > /etc/apt/sources.list <<EOF_APT_CHROOTED
    deb ${APT_MIRROR} $OS_DISTRIBUTION main non-free non-free-firmware contrib
    deb-src ${APT_MIRROR} $OS_DISTRIBUTION main non-free non-free-firmware contrib

    deb ${APT_MIRROR} $OS_DISTRIBUTION-security main non-free non-free-firmware contrib
    deb-src ${APT_MIRROR} $OS_DISTRIBUTION-security main non-free non-free-firmware contrib

    # $OS_DISTRIBUTION-updates, to get updates before a point release is made
    deb ${APT_MIRROR} $OS_DISTRIBUTION-updates main non-free non-free-firmware contrib
    deb-src ${APT_MIRROR} $OS_DISTRIBUTION-updates main non-free non-free-firmware contrib

    deb ${APT_MIRROR} $OS_DISTRIBUTION-backports main non-free non-free-firmware contrib

    # pre-release repository : dedeb-srcb ${APT_MIRROR} $OS_DISTRIBUTION-backports main non-free non-free-firmware contrib
EOF_APT_CHROOTED

cat /etc/apt/sources.list

# Update the repository cache
apt update
apt upgrade -y

# Install helpers
apt install -y --no-install-recommends linux-generic locales tzdata keyboard-configuration console-setup

# Note : You should always enable the en_US.UTF-8 locale because some programs require it.
echo "Configure packages to customize local and console properties..."
dpkg-reconfigure locales tzdata keyboard-configuration console-setup

# ZFS Configuration - Install required packages

apt install -y gdisk parted shim-signed mokutil dkms zfs-dkms zfsutils-linux zfs-initramfs

apt install -y dosfstools efibootmgr curl mc openssh-server
# Depricated  # echo "REMAKE_INITRD=yes" > /etc/dkms/zfs.conf

# Enable systemd ZFS services

systemctl enable zfs.target
systemctl enable zfs-import-cache
systemctl enable zfs-mount
systemctl enable zfs-import.target
systemctl enable zfs-import-scan

# Configure initramfs-tools
# Unencrypted No required steps

# Rebuild the initramfs
update-initramfs -c -k all

# Install and configure ZFSBootMenu
# Set ZFSBootMenu properties on datasets
# Assign command-line arguments to be used when booting the final kernel. 
# Because ZFS properties are inherited, assign the common properties to the ROOT dataset so all children will inherit common arguments by default.

zfs set org.zfsbootmenu:commandline="quiet" $ZPOOL_NAME/ROOT

# Create a vfat filesystem
mkfs.vfat -F32 "$BOOT_DEVICE"

# Add and Activate a Swap Partition
mkswap "$SWAP_DEVICE"
swapon "$SWAP_DEVICE"

# Find the UUID of the new swap partition: blkid
blkid | grep swap

# Create an fstab entry and mount for the BOOT_DEVICE
echo "\$(blkid | grep "$BOOT_DEVICE" | cut -d ' ' -f 2) /boot/efi vfat defaults 0 0" >> /etc/fstab

# Make Swap Permanent (/etc/fstab)
# Add this line to the end: UUID=SWAP_DEVICE-uuid-here none swap sw 0 0
echo "\$(blkid | grep "$SWAP_DEVICE" | cut -d ' ' -f 2) none swap sw 0 0" >> /etc/fstab

cat /etc/fstab

mkdir -p /boot/efi
mount /boot/efi

# Install ZFSBootMenu

# Fetch a prebuilt ZFSBootMenu EFI executable, saving it to the EFI system partition:

mkdir -p /boot/efi/EFI/ZBM
curl -o /boot/efi/EFI/ZBM/VMLINUZ.EFI -L "$ZBM_EFI_PATH"
cp /boot/efi/EFI/ZBM/VMLINUZ.EFI /boot/efi/EFI/ZBM/VMLINUZ-BACKUP.EFI

# Configure EFI boot entries

mount -t efivarfs efivarfs /sys/firmware/efi/efivars

efibootmgr -c -d "$BOOT_DISK" -p "$BOOT_PART" \
  -L "ZFSBootMenu (Backup)" \
  -l '\EFI\ZBM\VMLINUZ-BACKUP.EFI'

efibootmgr -c -d "$BOOT_DISK" -p "$BOOT_PART" \
  -L "ZFSBootMenu" \
  -l '\EFI\ZBM\VMLINUZ.EFI'

# Install system utilities
echo "Installing system utilities..."
apt install -y systemd-timesyncd net-tools iproute2 isc-dhcp-client iputils-ping traceroute curl wget dnsutils
apt install -y ethtool ifupdown tcpdump nmap nano htop openssh-server git tmux

# Installing KDE Plasma 6 Desktop environment with Xorg and Support compatibility for running individual X11 applications
echo "Installing  KDE Plasma 6 Desktop environment with Xorg"
echo "and Support compatibility for running individual X11 applications..."

export DEBIAN_FRONTEND=noninteractive
apt install -y kde-plasma-desktop dbus-x11 qt6-virtualkeyboard-plugin libreoffice libreoffice-qt6 snapd
apt install -y hunspell-ar hunspell-en-us hunspell-fr libreoffice-help-en-us libreoffice-help-fr libreoffice-l10n-ar libreoffice-l10n-fr hyphen-en-us hyphen-fr snapd 

# Configure libreoffice variables
    cat  > /usr/bin/libreoffice <<EOF_LIBREOFFICE
    # For libreoffice-qt6 plugin
    SAL_USE_VCLPLUGIN=qt6
    export SAL_USE_VCLPLUGIN

    # Increse the resolustion of libreoffice
    SAL_FORCEDPI=120
    export SAL_FORCEDPI
EOF_LIBREOFFICE

# Config IBus input method framework - setting X11-specific environment variables
touch /etc/environment.d/99-ibus.conf
    cat  > /etc/environment.d/99-ibus.conf <<EOF_IBUS_ENV
    # Unset legacy IBus variables for Wayland
    GTK_IM_MODULE=
    QT_IM_MODULE=
EOF_IBUS_ENV
    
# Creating ~/.xinitrc to explicitly launch KDE with a D-Bus session:
echo "Creating /home/$USERNAME/.xinitrc to explicitly launch KDE with a D-Bus session..."
echo 'exec dbus-launch --exit-with-session startplasma-x11' > /home/$USERNAME/.xinitrc
chmod +x ~/.xinitrc

usermod -aG sudo,audio,cdrom,dip,floppy,plugdev,operator,netdev,video,render $USERNAME
export DEBIAN_FRONTEND=interactive
sudo su $USERNAME -c "snap install bare core18 core20 core22 core24 mesa-2404 telegram-desktop"

# Installing KDE Plasma 6 Desktop environment with xserver-xorg
# echo "Installing KDE Plasma 6 Desktop environment with xserver-xorg..."
# apt install -y sddm dbus   
# apt install -y dbus-user-session dbus-x11 

systemctl start sddm
systemctl enable sddm
systemctl status sddm

systemctl start dbus
systemctl enable dbus
systemctl status dbus

# Installing IDE Pycharm-Community | PyCharm Installation Instructions : From https://wiki.debian.org/JetBrains
echo "Installing IDE Pycharm-Community..."

curl -s https://s3.eu-central-1.amazonaws.com/jetbrains-ppa/0xA6E8698A.pub.asc | gpg --dearmor |  tee /usr/share/keyrings/jetbrains-ppa-archive-keyring.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/jetbrains-ppa-archive-keyring.gpg] http://jetbrains-ppa.s3-website.eu-central-1.amazonaws.com any main" |  tee /etc/apt/sources.list.d/jetbrains-ppa.list > /dev/null
 apt update
apt install -y pycharm-community

# In Debian start and enable SSH server
echo "Starting and enabling SSH server..."
 systemctl start ssh
 systemctl enable ssh
 systemctl status ssh

# Configure Debian Networking

# Check available network interfaces
ip addr show

touch /etc/network/interfaces.d/iface_lo.conf
    cat > /etc/network/interfaces.d/iface_lo.conf <<EOF_IF_LO
    auto lo
    iface lo inet loopback
EOF_IF_LO

touch /etc/network/interfaces.d/iface_$IF_PHY.conf
    cat > /etc/network/interfaces.d/iface_$IF_PHY.conf <<EOF_IF_PHY
    # VirtualBox Nat Adapter - For internet connectivity
    allow-hotplug $IF_PHY
    auto $IF_PHY
    iface $IF_PHY inet static
        address $IF_PHY_ADDRESS
        netmask $IF_PHY_NETMASK
        gateway $IF_PHY_GATEWAY

    ifup $IF_PHY
EOF_IF_PHY

touch /etc/network/interfaces.d/iface_$IF_PHY_HOA.conf
    cat > /etc/network/interfaces.d/iface_$IF_PHY_HOA.conf <<EOF_IF_PHY_HOA
    # VirtualBox Host Only Adapter - For Lan connectivity
    allow-hotplug $IF_PHY_HOA
    auto $IF_PHY_HOA
    iface $IF_PHY_HOA inet static
        address $IF_PHY_ADDRESS_HOA
        netmask $IF_PHY_NETMASK_HOA
        gateway $IF_PHY_NETWORK_HOA

    ifup $IF_PHY_HOA
EOF_IF_PHY_HOA

cat /etc/network/interfaces.d/*

# Prepare for first boot
# Exit the chroot, unmount everything

exit
EOF_CHROOT
umount -n -R $MOUNT_POINT

# Export the zpool and reboot
zpool export $ZPOOL_NAME

# reboot
echo "ZFS Boot Menu installation complete. You may reboot your system now."

