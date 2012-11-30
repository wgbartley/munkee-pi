#!/bin/bash
# Resources, inspirations, and notable mentions:
#  - http://www.kmp.or.at/~klaus/raspberry/build_rpi_sd_card.sh
#  - http://www.cnx-software.com/2012/07/31/84-mb-minimal-raspbian-armhf-image-for-raspberry-pi/
#  - http://raspberrypi.stackexchange.com/questions/855/is-it-possible-to-update-upgrade-and-install-software-before-flashing-an-image
#  - http://www.raspberrypi.org/phpBB3/viewtopic.php?t=13962&p=171202
#  - http://xecdesign.com/qemu-emulating-raspberry-pi-the-easy-way/
#  - https://github.com/asb/raspi-config/blob/master/raspi-config

# Check for root
if [ $EUID -ne 0 ]; then
  echo "this tool must be run as root"
  exit 1
fi


# Install needed packages
apt-get -yqq install wget unzip kpartx qemu-user-static secure-delete


# Build environment
home=`pwd`
build="./rpi"
rootfs="${build}/mount"
bootfs="${rootfs}/boot"

mkdir -p "${bootfs}"


# Get the Occidentalis image
occ_ref="http://learn.adafruit.com/adafruit-raspberry-pi-educational-linux-distro/occidentalis-v0-dot-2"
occ_url="http://adafruit-raspberry-pi.s3.amazonaws.com/Occidentalisv02.zip"
occ_zip="${build}/occ.zip"
occ_work="${build}/occ.work.img"
occ_final="${build}/occ.final.img"

# If the working copy exists, delete it.
if [ -f "${occ_work}" ]; then
	echo "Deleting ${occ_work} (starting from scratch) ..."
	rm -f "${occ_work}"
fi


# Check if the zip exists.  If not, download it.
if [ ! -f "${occ_zip}" -a ! -f "${occ_work}" ]; then
	echo "Downloading ${occ_url} ... "
	wget --referer="${occ_ref}" "${occ_url}" -O "${occ_zip}"
fi


# If the zip exists but the img doesn't, extract it.
if [ -f "${occ_zip}" -a ! -f "${occ_work}" ]; then
	echo "Extracting ${occ_zip} ..."
	unzip -p "${occ_zip}" > "${occ_work}"
fi


# Mount the image
echo "Mounting ..."
device=`kpartx -va "${occ_work}" | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
device="/dev/mapper/${device}"
bootp="${device}p1"
rootp="${device}p2"

mount "${rootp}" "${rootfs}"
mount "${bootp}" "${bootfs}"

mount --rbind /dev "${rootfs}/dev"
mount -t proc none "${rootfs}/proc"
mount -o bind /sys "${rootfs}/sys"


# Copy qemu-arm-static so we can chroot
cp `which qemu-arm-static` "${rootfs}/usr/bin/"


# Time to start hacking away
# Do not show raspi-config on launch
rm -f "${rootfs}/etc/profile.d/raspi-config.sh"

# Add custom motd on login
cp "./custom-motd.sh" "${rootfs}/etc/profile.d/motd.sh"

# Custom first boot script
cp "./custom-bootonce.sh" "${rootfs}/etc/init.d/bootonce"

# Pre-chroot settings
echo "nameserver 8.8.8.8" > "${rootfs}/etc/resolv.conf"
echo "nameserver 8.8.4.4" >> "${rootfs}/etc/resolv.conf"


# Prepare to chroot!
cd "${home}"
cd "${rootfs}"

echo "#!/bin/bash
echo \"Apt update ...\"
apt-get update

echo \"Purge un-needed packages\"
apt-get -yqq purge xserver-common xinit x11-xserver-utils xinit libsmbclient x11-utils \
	x11-common x11-xkb-utils xarchiver xauth xkb-data console-setup lightdm \
	libx{composite,cb,cursor,damage,dmcp,ext,font,ft,i,inerama,kbfile,klavier,mu,pm,randr,render,res,t,xf86}* \
	lxde* lx{input,menu-data,panel,polkit,randr,session,session-edit,shortcut,task,terminal} \
	obconf openbox gtk* libgtk* python-pygame python-tk python3-tk scratch tsconf \
	desktop-file-utils xdg-utils ttf-freefont ttf-dejavu-core samba-common \
	raspberrypi-artwork python3 menu-xdg geoip-database fonts-freefont-ttf cifs-utils \
	omxplayer nfs-common wget python netcat-traditional netcat-openbsd libgfortran3 \
	libgeoip1 curl libfreetype6 git gcc-4.4-base:armhf gcc-4.5-base:armhf gcc-4.6-base:armhf \
	ca-certificates libraspberrypi-doc xkb-data fonts-freefont-ttf locales manpages python2.7

echo \"Purge dev packages\"
apt-get -yqq force-yes purge `dpkg --get-selections | grep \"\-dev\" | sed s/install//`

echo \"Purge sound packages\"
apt-get -yqq purge `dpkg --get-selections | grep -v \"deinstall\" | grep sound | sed s/install//`

echo \"Upgrade packages\"
apt-get -yqq dist-upgrade

echo \"Perform auto-remove\"
apt-get -yqq autoremove

echo \"Perform clean\"
apt-get clean

echo \"Delete the pi user\"
deluser pi
rm -rf /home/pi

echo \"Set root password to raspberry\"
echo \"root:raspberry\" | chpasswd


echo \"Make /etc/profile.d/motd.sh executable\"
chmod +x /etc/profile.d/motd.sh
echo \"Make /etc/init.d/bootonce executable\"
chmod +x /etc/init.d/bootonce
echo \"Enable bootonce\"
update-rc.d bootonce defaults


echo \"Clean out apt\"
rm -f /var/lib/apt/lists/archive.* /var/lib/apt/lists/mirrordirector.* /var/cache/apt/archives/*.deb


echo \"Remove misc stuff\"
rm -rf /root/.rpi-firmware /lib/modules.bak /boot.bak /boot/issue.txt /opt /srv /var/cache/debconf/*.dat-old
rm -rf /etc/X11 /etc/Xcd /etc/xdg /etc/gconf

echo \"Empty out /etc/motd\"
echo \"\" > /etc/motd


echo \"Clean out logs\"
rm -f /var/log/*.log /var/log/dmesg.* /var/log/syslog.* /var/backups/*.gz
echo \"'\"> /var/log/auth.log
echo \"\" /var/log/bootstrap.log
echo \"\" > /var/log/daemon.log
echo \"\" > /var/log/dpkg.log
echo \"\" /var/log/kern.log
echo \"\" > /var/log/messages


echo \"Disable and delete /var/swap\"
swapoff -a
rm -f /var/swap
" > workhorse
chmod +x workhorse
LANG=C chroot ./ /workhorse
cd "${home}"


# Sleep a little bit to settle things
sleep 2


# Remove qemu-arm-static
echo "Cleaning up ..."
rm -f "${rootfs}/usr/bin/qemu-arm-static"


# Remove /root/.bash_history
rm -f "${rootfs}/root/.bash_history"


# Fill empty space with 0's
echo "Zero-ing out empty space on ${bootfs} ..."
sfill -z -l -l -f "${bootfs}"
sleep 1
sync
sleep 1
echo "Zero-ing out empty space on ${rootfs} ..."
sfill -z -l -l -f "${rootfs}"
sleep 1


# Check for open processes
psaux=`ps aux | grep 'qemu-arm-static' | grep -v 'grep' | wc -l`
if [ ! "${psaux}" -eq 0 ]; then
	echo "Killing open qemu-arm-static processes"
	ps aux | grep 'qemu-arm-static' | grep -v 'grep' | awk '{print $2}' | xargs kill -9
	sleep 1
fi;


# Unmount
echo "Unmounting ..."
echo "Unmount ${rootfs}/sys"
umount -f "${rootfs}/sys"
sleep 1
echo "Unmount ${rootfs}/proc"
umount -f "${rootfs}/proc"
sleep 1
echo "Unmount ${rootfs}/dev/pts"
umount -f "${rootfs}/dev/pts"
sleep 1
echo "Unmount ${rootfs}/dev"
umount -f "${rootfs}/dev"
sleep 1
echo "Unmount ${rootfs}/boot"
umount -f "${rootfs}/boot"
sleep 1
echo "Unmount ${rootfs}"
umount -f "${rootfs}"
sleep 1
#cat /proc/mounts | awk '{print $2}' | grep "^${rootfs}" | sort -r | xargs umount -f
#sleep 2


# Resize the filesystem
e2fsck -fy ${rootp}
sleep 1
size=`resize2fs -fM ${rootp} | grep 'The filesystem on' | awk '{ print $7 }'`
size=`echo "${size} 4" | awk '{print int(($1*$2)+1)}'`
echo "Minimum size: ${size}KB"
size=`echo "${size} 1.1" | awk '{print int(($1*$2)+1)}'`
echo "Target size: ${size}KB"
resize2fs -f ${rootp} ${size}K
size=`echo "${size} 60000" | awk '{print int(($1+$2))}'`


# Make a copy of the image and zip it
dd if=$occ_work of=$occ_final bs=1K count=$size
gzip -v9 $occ_final


# Un-map the image and delete the working copy
sleep 1
sync
sleep 1
kpartx -d "${occ_work}"
rm -f ${occ_work}
