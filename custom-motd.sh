#!/bin/sh

uname -a

echo ""

echo "   System information as of $(date)"
echo ""

system_load=`uptime | awk '{print $11}'`
uptime=`uptime | awk '{sub(/,/, ""); print $3 " " $4}'`
processes=`ps aux | wc -l`
users=`who | wc -l`
usage=`df -h | grep -v 'Filesystem' | head -1 | awk '{print $3 " (" $5 ") of " $2}'`
ips=`ifconfig | grep 'inet addr' | grep -v 'inet addr:127' | awk '{split($2,a,":"); print a[2]}'`



echo "   System load        : ${system_load}"
echo "   Uptime             : ${uptime}"
echo "   Processes          : ${processes}"
echo "   Users logged in    : ${users}"
echo "   Usage of /         : ${usage}"

first_ip=0
for ip in $ips; do
        if [ "$first_ip" -eq 0 ]; then
                first_ip=1
                echo "   IP Addresses       : ${ip}"
        else
                echo "                      : ${ip}"
        fi
done

echo ""

