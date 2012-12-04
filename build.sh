#!/bin/bash
# Resources, inspirations, and notable mentions:
#  - http://www.kmp.or.at/~klaus/raspberry/build_rpi_sd_card.sh
#  - http://www.cnx-software.com/2012/07/31/84-mb-minimal-raspbian-armhf-image-for-raspberry-pi/
#  - http://raspberrypi.stackexchange.com/questions/855/is-it-possible-to-update-upgrade-and-install-software-before-flashing-an-image
#  - http://www.raspberrypi.org/phpBB3/viewtopic.php?t=13962&p=171202
#  - http://xecdesign.com/qemu-emulating-raspberry-pi-the-easy-way/
#  - https://github.com/asb/raspi-config/blob/master/raspi-config
#  - http://raphaelhertzog.com/2010/11/15/save-disk-space-by-excluding-useless-files-with-dpkg/

# Check for root
if [ $EUID -ne 0 ]; then
  echo "this tool must be run as root"
  exit 1
fi


# Clear the screen
for i in {1..80}; do
	echo ""
done
clear


# Install needed packages
apt-get -yqq install wget unzip kpartx qemu-user-static secure-delete


# Build environment
home=`pwd`
# Where to mount the image and do most of the work
build="./work"
# Where to download and store the images
images="./images"
# Mount point for the root filesystem
rootfs="${build}/mount"
# Mount point for the /boot filesystem
bootfs="${rootfs}/boot"

# Create the bootfs directory (which includes the rootfs directory)
mkdir -p "${bootfs}"


# Get the Occidentalis image
# Refferor to pass in the wget headers
occ_ref="http://learn.adafruit.com/adafruit-raspberry-pi-educational-linux-distro/occidentalis-v0-dot-2"
# URL of the actual download
occ_url="http://adafruit-raspberry-pi.s3.amazonaws.com/Occidentalisv02.zip"
# Where to save the zip
occ_zip="${images}/occ.zip"
# The image we'll be working with
occ_work="${images}/occ.work.img"
# The final, shrunken image
occ_final="${images}/occ.final.img"


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
loop_device=`kpartx -va "${occ_work}" | sed -E 's/.*(loop[0-9])p.*/\1/g' | head -1`
device="/dev/mapper/${loop_device}"
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

# Copy files from custom/
cp -rafv ${home}/custom/* "${rootfs}/"


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
apt-get -yq --force-yes purge xserver-common xinit x11-xserver-utils xinit libsmbclient x11-utils \
	x11-common x11-xkb-utils xarchiver xauth xkb-data console-setup lightdm \
	libx{composite,cb,cursor,damage,dmcp,ext,font,ft,i,inerama,kbfile,klavier,mu,pm,randr,render,res,t,xf86}* \
	lxde* lx{input,menu-data,panel,polkit,randr,session,session-edit,shortcut,task,terminal} \
	obconf openbox gtk* libgtk* python-pygame python-tk python3-tk scratch tsconf \
	desktop-file-utils xdg-utils ttf-freefont ttf-dejavu-core samba-common \
	raspberrypi-artwork python3 menu-xdg geoip-database fonts-freefont-ttf cifs-utils \
	omxplayer nfs-common wget python netcat-traditional netcat-openbsd libgfortran3 \
	libgeoip1 curl libfreetype6 git gcc-4.4-base:armhf gcc-4.5-base:armhf gcc-4.6-base:armhf \
	ca-certificates libraspberrypi-doc xkb-data fonts-freefont-ttf locales manpages python2.7 alsa-base

echo \"Purge dev packages\"
apt-get -yq --force-yes purge `dpkg --get-selections | grep \"\-dev\" | sed s/install//`

#echo \"Purge sound packages\"
#apt-get -yq --force-yes purge `dpkg --get-selections | grep -v \"deinstall\" | grep sound | sed s/install//`

echo \"Upgrade packages\"
apt-get -yq dist-upgrade

#echo \"Install debconf-utils\"
#apt-get -yqq install debconf-utils

#echo \"Set some default settings for localepurge\"
#echo \"localepurge localepurge/nopurge multiselect en, en_US.UTF-8\" | debconf-set-selections
#DEBIAN_FRONTEND=noninteractive dpkg-reconfigure localepurge

#echo \"Install localepurge\"
#apt-get -yqq install localepurge

echo \"Update rpi firmware\"
rpi-update

echo \"Perform auto-remove\"
apt-get -yq autoremove

echo \"Perform clean\"
apt-get autoclean
apt-get clean

echo \"Delete the pi user\"
deluser pi
rm -rf /home/pi

echo \"Set root password to raspberry\"
echo \"root:raspberry3.14\" | chpasswd


echo \"Enable bootonce\"
update-rc.d bootonce defaults


echo \"Clean out apt\"
rm -f /var/lib/apt/lists/archive.* /var/lib/apt/lists/mirrordirector.* /var/cache/apt/archives/*.deb


echo \"Remove misc stuff\"
rm -rf /root/.rpi-firmware /lib/modules.bak /boot.bak /boot/issue.txt /opt /srv /var/cache/debconf/*.dat-old
rm -rf /etc/X11 /etc/Xcd /etc/xdg /etc/gconf /etc/ConsoleKit /var/log/ConsoleKit /usr/share/locale/*

echo \"Empty out /etc/motd\"
echo \"\" > /etc/motd


echo \"Clean out logs\"
rm -rf /var/log/*.log /var/log/dmesg.* /var/log/syslog.* /var/backups/*.gz /var/log/debug.* \
       /var/log/ConsoleKit /var/log/auth.* /var/log/apt/history.* /var/log/apt/term.* \
       /usr/share/images/desktop-base
echo \"'\"> /var/log/auth.log
echo \"\" /var/log/bootstrap.log
echo \"\" > /var/log/daemon.log
echo \"\" > /var/log/dpkg.log
echo \"\" /var/log/kern.log
echo \"\" > /var/log/messages
echo \"\" > /var/log/syslog
echo \"\" > /var/log/dmesg
echo \"\" > /var/log/debug
echo \"\" > /var/log/mail.err
echo \"\" > /var/log/mail.info
echo \"\" > /var/log/mail.log
echo \"\" > /var/log/news/news.crit
echo \"\" > /var/log/news/news.err
echo \"\" > /var/log/news/news.notice
echo \"\" > /var/log/apt/history.log
echo \"\" > /var/log/apt/term.log


echo \"Disable and delete /var/swap\"
swapoff -a
rm -f /var/swap


echo \"Final filesystem size\"
cd /
df -h
du -hs .
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
#echo "Zero-ing out empty space on ${bootfs} ..."
#sfill -z -l -l -f "${bootfs}"
#sleep 1
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
size=`echo "${size} 1.2" | awk '{print int(($1*$2)+1)}'`
echo "Target size: ${size}KB"

fdisk "/dev/${loop_device}" << EOF
d
2

n
p
2
122880
+${size}K
p
w
EOF

partprobe "/dev/${loop_device}"
sync

resize2fs -f ${rootp} ${size}K
size=`echo "${size} 60000" | awk '{print int(($1+$2))}'`


# Make a copy of the image and zip it
dd if=$occ_work of=$occ_final bs=1K count=$size
#gzip -v9 $occ_final


# Un-map the image and delete the working copy
sleep 1
sync
sleep 1
kpartx -d "${occ_work}"
#rm -f ${occ_work}
