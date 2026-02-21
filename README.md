# Debian 13, KDE Plasma 6, xorg and ZFSBootMenu Installation Script
Bash script to install Debian 13, KDE Plasma 6, xserver-xorg with ZFS on Root and ZFSBootMenu, the ZFSBootMenu page reference is : https://docs.zfsbootmenu.org/en/latest/guides/debian/uefi.html

## Prerequisites

- A live installation environment (e.g., Debian Live)
   1. **Remarque :**
      ```bash
      The first task is to download the latest debian-live-13.X.X-amd64-standard.iso,
      this necessary to don''t have a miss matches packages between the live iso image and the
      "apt update && apt upgrade" instruction, causing the system to not be able loading the ZFS modules
      ```
- A disk available for partitioning and installation (existing data will be erased)
- Network connection for downloading packages and files

## Usage

1. **Configure Debian Networking**
   
   Boot into your live environment, open a terminal, run the following

   ```bash
   # Switch to a root shell
   root@debian:~# sudo -i
   root@debian:~# bash

   # Check available network interfaces
   root@debian:~# ip addr show

   # edit the network interfaces file to insure internet connectivity
   root@debian:~# nano /etc/network/interfaces
   auto lo
   iface lo inet loopback

   # This is a virtualBox Nat Adapter, change must be done to reflect your configuration
   allow-hotplug enp0s3
   auto enp0s3
   iface enp0s3 inet static
         address 10.0.2.228
         netmask 255.255.255.0
         gateway 10.0.2.2
   ifup enp0s3

   #----------------------------------
   root@debian:~# systemctl restart networking.service
   # Do not test the connectivity by a ping, it doesn't work,
   # but you can update the system by "apt update && apt upgrade"

   # Configure and update APT
   root@debian:~# nano /etc/apt/sources.list
   deb http://deb.debian.org/debian/ trixie main non-free non-free-firmware contrib
   deb-src http://deb.debian.org/debian/ trixie main non-free non-free-firmware contrib

   root@debian:~# apt update && apt upgrade
   ```

2. **Downloading the script and editing it**
   
   Run the following to start the script

   ```bash   
   root@debian:~# apt install curl
   root@debian:~# curl -O https://raw.githubusercontent.com/Rai-Mohammed/debian13-kde6-xorg-zfsbootmenu/main/debian13-kde6-xorg-zfsbootmenu.sh

   # Make the necessary changes to the installation script
   root@debian:~# nano debian13-kde6-xorg-zfsbootmenu.sh

   root@debian:~# chmod +x debian13-kde6-xorg-zfsbootmenu.sh
   root@debian:~# ./debian13-kde6-xorg-zfsbootmenu.sh
   ```
