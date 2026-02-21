#!/bin/bash

# Bash script to install Debian 13, KDE Plasma 6, xserver-xorg with ZFS on Root and ZFSBootMenu

# Automatically set other variables

# First, define variables that refer to the disk and partition number that will hold boot files:
# Single SATA disk :
BOOT_DISK="/dev/sda"
BOOT_PART="1"
BOOT_DEVICE="${BOOT_DISK}${BOOT_PART}"

# Next, define variables that refer to the disk and partition number that will hold the ZFS pool:
# Single SATA disk :
POOL_DISK="/dev/sda"
POOL_PART="2"
POOL_DEVICE="${POOL_DISK}${POOL_PART}"

ZPOOL_NAME="zroot"

KERNEL_VERSION=$(uname -r)  # Automatically get current kernel version
MOUNT_POINT="/mnt"
OS_ID=$(source /etc/os-release && echo "$OS_ID")  # Get OS ID from /etc/os-release
OS_DISTRIBUTION="trixie"
CPU_ARCH="intel"
USERNAME="fill_your_user_name"
USER_PASSWORD="fill_your_user_password"
ROOT_PASSWORD="fill_your_root_password"
HOSTNAME="fill_your_hostname"

IF_PHY="em"
IF_PHY_ADDRESS="10.0.2.288"
IF_PHY_NETMASK="255.255.255.0"
IF_PHY_GATEWAY="10.0.2.2"
#----------------------------------
# From : https://docs.zfsbootmenu.org/en/latest/guides/debian/uefi.html#

# Install helpers
apt install -y ca-certificates apt-transport-https
apt install -y debootstrap gdisk dkms linux-headers-$KERNEL_VERSION         #linux-headers-amd64
apt install -y zfsutils-linux


# Generate /etc/hostid
zgenhostid -f 0x00bab10c

# Define disk variables
# Verify your target disk devices with lsblk
lsblk

# Disk preparation
# Wipe partitions
zpool destroy -f $ZPOOL_NAME
zpool clear -F $ZPOOL_NAME
zpool labelclear -f $POOL_DEVICE

wipefs -a "$POOL_DISK"
wipefs -a "$BOOT_DISK"

sgdisk --zap-all "$POOL_DISK"
sgdisk --zap-all "$BOOT_DISK"

# Create EFI boot partition
sgdisk -n "${BOOT_PART}:1m:+512m" -t "${BOOT_PART}:ef00" "$BOOT_DISK"

# Create zpool partition
sgdisk -n "${POOL_PART}:0:-10m" -t "${POOL_PART}:bf00" "$POOL_DISK"

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
 -m none $ZPOOL_NAME $POOL_DEVICE

# Create initial file systems

 zfs create -o mountpoint=none $ZPOOL_NAME/ROOT
 zfs create -o mountpoint=/ -o canmount=noauto $ZPOOL_NAME/ROOT/$OS_ID
 zfs create -o mountpoint=/home $ZPOOL_NAME/home

 zpool set bootfs=$ZPOOL_NAME/ROOT/$OS_ID $ZPOOL_NAME

# Export, then re-import with a temporary mountpoint of $MOUNT_POINT

 zpool export $ZPOOL_NAME
 zpool import -N -R $MOUNT_POINT $ZPOOL_NAME
 zfs mount $ZPOOL_NAME/ROOT/$OS_ID
 zfs mount $ZPOOL_NAME/home


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
# Basic Debian Configuration
# Set a hostname

echo "$HOSTNAME" > /etc/hostname
echo -e "127.0.1.1\t $HOSTNAME" >> /etc/hosts

# Set a root password
echo "Setting root password..."
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user and set password
echo "Creating user and setting permissions..."
useradd $USERNAME --shell /bin/bash --home /home/$USERNAME --allow-bad-names
usermod -aG sudo,audio,cdrom,dip,floppy,netdev,plugdev,video $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Check if the directory exists and confirm the user''s settings.

# Check if the directory /home/$USERNAME exists.
# You can also use the id command to see if the user exists and what their home directory is set to.
# Check the /etc/passwd file to see the actual home directory specified for the user.
cat /etc/passwd | grep $USERNAME

# Set correct ownership and permissions.
# The home directory must be owned by the user.
#  chown $USERNAME:$USERNAME /home/$USERNAME

# The user needs permission to enter the directory. The 755 permission is a good default, which allows the owner to read, write, and execute, and others to read and execute.
#  chmod 755 /home/$USERNAME

# Copy default shell files (if necessary).
# If you created the directory manually, you may need to copy default shell configuration files.
# cp -r /etc/skel/. /home/$USERNAME/
# chown -R $USERNAME:$USERNAME /home/$USERNAME/

#For a more automated and robust solution, use mkhomedir_helper if available


# Configure apt sources

    cat <<EOF_APT > /etc/apt/sources.list
    deb http://deb.debian.org/debian/ $OS_DISTRIBUTION main non-free non-free-firmware contrib
    deb-src http://deb.debian.org/debian/ $OS_DISTRIBUTION main non-free non-free-firmware contrib

    deb http://deb.debian.org/debian-security $OS_DISTRIBUTION-security main non-free non-free-firmware contrib
    deb-src http://deb.debian.org/debian-security/ $OS_DISTRIBUTION-security main non-free non-free-firmware contrib

    # $OS_DISTRIBUTION-updates, to get updates before a point release is made
    deb http://deb.debian.org/debian $OS_DISTRIBUTION-updates main non-free non-free-firmware contrib
    deb-src http://deb.debian.org/debian $OS_DISTRIBUTION-updates main non-free non-free-firmware contrib

    # pre-release repository : deb http://deb.debian.org/debian $OS_DISTRIBUTION-backports main contrib non-free non-free-firmware contrib
    EOF_APT

# Update the repository cache
apt update

# Install helpers
apt install -y ca-certificates apt-transport-https $CPU_ARCH-microcode
apt install -y gdisk dkms linux-headers-amd64         #linux-headers-amd64
apt install -y zfsutils-linux

# Install additional base packages
apt install -y locales locales-all keyboard-configuration console-setup

# Install system utilities
echo "Installing system utilities..."
apt install -y systemd-timesyncd net-tools iproute2 isc-dhcp-client iputils-ping traceroute curl wget dnsutils 
apt install -y ethtool ifupdown tcpdump nmap nano vim htop openssh-server git tmux

# Note : You should always enable the en_US.UTF-8 locale because some programs require it.
echo "Configure packages to customize local and console properties..."
dpkg-reconfigure locales tzdata keyboard-configuration console-setup


# ZFS Configuration - Install required packages

apt install linux-headers-amd64 linux-image-amd64 zfs-initramfs dosfstools curl efibootmgr
echo "REMAKE_INITRD=yes" > /etc/dkms/zfs.conf

# Enable systemd ZFS services

systemctl enable zfs.target
systemctl enable zfs-import-cache
systemctl enable zfs-mount
systemctl enable zfs-import.target

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

# Create an fstab entry and mount

    cat << EOF_FSTAB >> /etc/fstab
    $( blkid | grep "$BOOT_DEVICE" | cut -d ' ' -f 2 ) /boot/efi vfat defaults 0 0
    EOF_FSTAB

mkdir -p /boot/efi
mount /boot/efi

# Install ZFSBootMenu
# Fetch a prebuilt ZFSBootMenu EFI executable, saving it to the EFI system partition:

mkdir -p /boot/efi/EFI/ZBM
curl -o /boot/efi/EFI/ZBM/VMLINUZ.EFI -L https://get.zfsbootmenu.org/efi
cp /boot/efi/EFI/ZBM/VMLINUZ.EFI /boot/efi/EFI/ZBM/VMLINUZ-BACKUP.EFI

# Configure EFI boot entries

mount -t efivarfs efivarfs /sys/firmware/efi/efivars

efibootmgr -c -d "$BOOT_DISK" -p "$BOOT_PART" \
  -L "ZFSBootMenu (Backup)" \
  -l '\EFI\ZBM\VMLINUZ-BACKUP.EFI'

efibootmgr -c -d "$BOOT_DISK" -p "$BOOT_PART" \
  -L "ZFSBootMenu" \
  -l '\EFI\ZBM\VMLINUZ.EFI'

# Installing KDE Plasma 6 Desktop environment with xserver-xorg
echo "Installing KDE Plasma 6 Desktop environment with xserver-xorg..."
apt install -y sddm dbus xorg xserver-xorg plasma-desktop kde-config-sddm plasma-workspace task-kde-desktop
apt install -y dbus-user-session dbus-x11 kwin-x11 qt6-virtualkeyboard-plugin

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
    cat <<EOF_IF_LO > /etc/network/interfaces.d/iface_lo.conf
    auto lo
    iface lo inet loopback
    EOF_IF_LO

touch /etc/network/interfaces.d/iface_$IF_PHY.conf
    cat <<EOF_IF_PHY > /etc/network/interfaces.d/iface_$IF_PHY.conf
    # VirtualBox Nat Adapter - For internet connectivity
    allow-hotplug $IF_PHY
    auto $IF_PHY
    iface $IF_PHY inet static
        address $IF_PHY_ADDRESS
        netmask $IF_PHY_NETMASK
        gateway $IF_PHY_GATEWAY
    ifup $IF_PHY
    EOF_IF_PHY

# Prepare for first boot
# Exit the chroot, unmount everything

exit
EOF_CHROOT
umount -n -R $MOUNT_POINT

# Export the zpool and reboot
zpool export $ZPOOL_NAME

# reboot
echo "ZFS Boot Menu installation complete. You may reboot your system now."
