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
ZBM_EFI_PATH="https://get.zfsbootmenu.org/efi"

KERNEL_VERSION=$(uname -r)  # Automatically get current kernel version
MOUNT_POINT="/mnt"
OS_ID=$(source /etc/os-release && echo "$ID")  # Get OS ID from /etc/os-release
OS_DISTRIBUTION="questing"
APT_MIRROR="http://archive.ubuntu.com/ubuntu/"
CPU_ARCH="intel"
USERNAME="fill_your_username"
USER_PASSWORD="fill_your_user_password"
ROOT_PASSWORD="fill_your_root_password"
HOSTNAME="fill_your_hostname"

IF_PHY_DNS="8.8.4.4"

IF_PHY_NET="enp0s3"
IF_PHY_ADDRESS_NET="10.0.2.228"
IF_PHY_NETMASK_NET="24"
IF_PHY_GATEWAY_NET="10.0.2.2"

IF_PHY_HOA="enp0s8"
IF_PHY_ADDRESS_HOA="192.168.59.228"
IF_PHY_NETMASK_HOA="24"
IF_PHY_GATEWAY_HOA="192.168.59.1"
#----------------------------------
# From : https://docs.zfsbootmenu.org/en/latest/guides/debian/uefi.html#

# Install helpers
apt install -y debootstrap gdisk dkms zfs-dkms zfsutils-linux

# Generate /etc/hostid
zgenhostid -f

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

zpool status
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

cat /etc/hosts

# Set a root password
echo "Setting root password..."
echo "root:$ROOT_PASSWORD" | chpasswd

# Create user and set password
echo "Creating user and setting permissions..."
useradd $USERNAME --shell /bin/bash --home /home/$USERNAME 
usermod -aG sudo,audio,cdrom,dip,floppy,plugdev,operator,netdev,video $USERNAME
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

    cat  > /etc/apt/sources.list <<EOF_APT
    deb ${APT_MIRROR} $OS_DISTRIBUTION main restricted universe multiverse
    deb-src ${APT_MIRROR} $OS_DISTRIBUTION main restricted universe multiverse

    deb ${APT_MIRROR} $OS_DISTRIBUTION-security main restricted universe multiverse
    deb-src ${APT_MIRROR} $OS_DISTRIBUTION-security main restricted universe multiverse

    # $OS_DISTRIBUTION-updates, to get updates before a point release is made
    deb ${APT_MIRROR} $OS_DISTRIBUTION-updates main restricted universe multiverse
    deb-src ${APT_MIRROR} $OS_DISTRIBUTION-updates main restricted universe multiverse

    deb ${APT_MIRROR} $OS_DISTRIBUTION-backports main restricted universe multiverse

    # pre-release repository : dedeb-srcb ${APT_MIRROR} $OS_DISTRIBUTION-backports main contrib main restricted universe multiverse
EOF_APT

cat /etc/apt/sources.list

# Update the repository cache
apt update
apt upgrade -y

# Install helpers
apt install -y --no-install-recommends linux-generic locales keyboard-configuration console-setup shim-signed

apt install -y locales tzdata keyboard-configuration console-setup

# Note : You should always enable the en_US.UTF-8 locale because some programs require it.
echo "Configure packages to customize local and console properties..."
dpkg-reconfigure locales tzdata keyboard-configuration console-setup

# ZFS Configuration - Install required packages

apt install -y gdisk dkms zfs-dkms zfsutils-linux zfs-initramfs

apt install -y dosfstools efibootmgr curl ubuntu-server mc openssh-server
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

# Create an fstab entry and mount
echo "\$(blkid | grep "$BOOT_DEVICE" | cut -d ' ' -f 2) /boot/efi vfat defaults 0 0" >> /etc/fstab
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

# Installing Gnome Desktop environment with Wayland and Support compatibility for running individual X11 applications
echo "Installing Gnome Desktop environment with Wayland"
echo "and Support compatibility for running individual X11 applications..."
apt install -y ubuntu-desktop gnome-session gnome-session-common gnome-shell-ubuntu-extensions gnome-shell gnome-shell-common gnome-shell-extensions gnome-shell-extensions-common gnome-shell-extension-appindicator gnome-shell-extension-apps-menu gnome-shell-extension-auto-move-windows gnome-shell-extension-desktop-icons-ng apt install gnome-software gdm3 xwayland ubuntu-restricted-extras

 systemctl start gdm3
 systemctl enable gdm3
 systemctl status gdm3

# Installing IDE Pycharm-Community | PyCharm Installation Instructions : From https://wiki.debian.org/JetBrains
echo "Installing IDE Pycharm-Community..."



# Configure Ubuntu Networking

# Step : Configure Netplan

# Check available network interfaces
ip addr show

mkdir -p /etc/netplan

#touch /etc/network/interfaces.d/iface_lo.conf
#    cat > /etc/network/interfaces.d/iface_lo.conf <<EOF_IF_LO
#    auto lo
#    iface lo inet loopback
#EOF_IF_LO

touch /etc/netplan/01_ifaces_config.yaml
cat > /etc/netplan/01_ifaces_config.yaml <<EOF_IF_NETPLAN
network:
    version: 2
    renderer: networkd
    ethernets:
        # VirtualBox Nat Adapter - For internet connectivity
        ${IF_PHY_NET}:
            dhcp4: false
            accept-ra: true
            addresses: [${IF_PHY_ADDRESS_NET}/${IF_PHY_NETMASK_NET}]
            routes:
               - to: default
                 via: ${IF_PHY_GATEWAY_NET}
            nameservers:
                addresses: [${IF_PHY_DNS}]
        # VirtualBox Host Only Adapter - For Lan connectivity
        ${IF_PHY_HOA}:
            dhcp4: false
            accept-ra: true
            addresses: [${IF_PHY_ADDRESS_HOA}/${IF_PHY_NETMASK_HOA}]
            nameservers:
                addresses: [${IF_PHY_DNS}]
EOF_IF_NETPLAN

chmod 600 /etc/netplan/01_ifaces_config.yaml
netplan generate
netplan apply || true

# Step : Define New Routing Tables
touch /etc/iproute2/rt_tables
cat > /etc/iproute2/rt_tables <<EOF_IP_RT
1    table_net
2    table_hoa
EOF_IP_RT

# Step : Add Routes to the New Tables
ip route add default via ${IF_PHY_GATEWAY_NET} dev ${IF_PHY_NET} table table_net
ip route add default via ${IF_PHY_GATEWAY_HOA} dev ${IF_PHY_HOA} table table_net

touch /etc/rc.local
cat > /etc/rc.local <<EOF_RC
sudo ip route add default via ${IF_PHY_GATEWAY_NET} dev ${IF_PHY_NET} table table_net
sudo ip route add default via ${IF_PHY_GATEWAY_HOA} dev ${IF_PHY_HOA} table table_net
EOF_RC

# Step : Add Policy Routing Rules

ip rule add from ${IF_PHY_ADDRESS_NET}/${IF_PHY_NETMASK_NET} table table_net
ip rule add from ${IF_PHY_ADDRESS_HOA}/${IF_PHY_NETMASK_HOA} table table_hoa

# Step : Verify Configuration
ip route flush cache
ip rule show
ip route show table table_net
ip route show table table_hoa

# Prepare for first boot
# Exit the chroot, unmount everything

exit
EOF_CHROOT
umount -n -R $MOUNT_POINT

# Export the zpool and reboot
zpool export $ZPOOL_NAME

# reboot
echo "ZFS Boot Menu installation complete. You may reboot your system now."

