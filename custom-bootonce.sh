#!/bin/sh
### BEGIN INIT INFO
# Provides: Fancypants
# Required-Start:
# Required-Stop:
# Default-Start: 2 3 4 5
# Default-Stop:
# Short-Description: Scripts to run on first boot
# Description:
### END INIT INFO

. /lib/lsb/init-functions

case "$1" in
  start)
    log_daemon_msg "Starting boot_once" &&

    # Get the starting offset of the root partition
    PART_START=$(parted /dev/mmcblk0 -ms unit s p | grep "^2" | cut -f 2 -d:)
    [ "$PART_START" ] || return 1
    # Return value will likely be error for fdisk as it fails to reload the
    # partition table because the root fs is mounted
    fdisk /dev/mmcblk0 <<EOF
p
d
2
n
p
2
$PART_START

p
w
EOF

    # Grow the filesystem
    resize2fs /dev/mmcblk0p2 &&


    # Check for connectivity
    ping_recv=`ping -W 1 -c 1 www.google.com | grep ' packets transmitted, ' | awk '{print $4}'` &&

    if [ "$ping_recv" -eq 1 ]; then
      # Update apt
      apt-get update &&

      # Install common packages
      apt-get -y install tzdata wget curl ca-certificates locales git binutils console-data &&

      # Auto-update rpi firmware
      rpi-update
    fi


    # Enable SSH
    update-rc.d ssh enable &&
    invoke-rc.d ssh start &&


    # Set time zone
    echo "US/Eastern" > /etc/timezone &&
    dpkg-reconfigure -f noninteractive tzdata &&

    # Set language/locale
    echo "LAN=enUS" > /etc/default/locale &&
    dpkg-reconfigure -f noninteractive locales &&

    # Set keyboard layout
    echo "XKBMODEL=\"pc104\"" > /etc/default/keyboard &&
    echo "XKBLAYOUT=\"us\"" >> /etc/default/keyboard &&
    echo "XKBVARIANT=\"\"" >> /etc/default/keyboard &&
    echo "XKBOPTIONS=\"\"" >> /etc/default/keyboard &&
    echo "BACKSPACE=\"guess\"" >> /etc/default/keyboard &&

    # Remove this script
    rm /etc/init.d/boot_once &&
    dpkg-reconfigure -f noninteractive keyboard-configuration    update-rc.d boot_once remove &&
    log_end_msg $? &&

    # Reboot
    sync &&
    reboot

    ;;
  *)
    echo "Usage: $0 start" >&2
    exit 3
    ;;
esac
