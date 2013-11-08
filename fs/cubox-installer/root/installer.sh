#!/bin/bash

# Copyright (C) 2012 SolidRun ltd. Rabeeh Khoury <rabeeh@solid-run.com>
# Distributed under the terms of the GNU General Public License v2

TMP=`mktemp`
TMP1=`mktemp`
chmod +x $TMP

###########################################################
# Distro listing functions
###########################################################
function get_distro_list {
	\rm -rf dist.list
	wget -N --no-check-certificate https://raw.github.com/rabeeh/cubox-installer-scripts/master/dist.list
	cat dist.list | grep -v "#" > $TMP
	num=0
	while IFS=$'\t' read -r -a myArray; do
		echo $line
		echo ${myArray[0]}
		echo ${myArray[1]}
		echo ${myArray[2]}
		VAR1[$num]=${myArray[0]}
		VAR2[$num]=${myArray[1]}
		VAR3[$num]=${myArray[2]}
		VAR4[$num]=${myArray[3]}
		echo "Got ${VAR1[$num]} ${VAR2[$num]} ${VAR3[$num]} ${VAR4[$num]}"
		num=`expr $num + 1`
	done < $TMP
	DLG="dialog --menu \"Please choose package to install\" 40 120 120"
	for (( i=0 ; i<$num ; i++ )); do
		DLG+=" \"${VAR1[$i]}\" \"${VAR4[$i]}\""
	done
	echo $DLG > $TMP
	$TMP 2> $TMP1
	RSLT=`cat $TMP1`
	for (( PKG_IDX=0; PKG_IDX<$num ; PKG_IDX++)); do
		if [ "x$RSLT" == "x${VAR1[$PKG_IDX]}" ]; then
			break;
		fi
	done
	if [ $PKG_IDX -eq $num ]; then
		PKG_IDX=-1
	fi
}

#####################################################################
# General mass storage device checking and partition wiping functions
#####################################################################
function get_destination {
	dialog --menu "Please choose destination device to install to" 40 120 120 "/dev/mmcblk0" "microSD card on CuBox" 2> $TMP
	DST_DEV=`cat $TMP`
	echo "Destination device to install to is $DST_DEV"
}
function check_if_partitioned {
	echo "Checking $DST_DEV"
	NUM_OF_PARTS=`parted -s $DST_DEV print|awk '/^ / {print $1}' | wc -l`
	if [ $NUM_OF_PARTS -ge 1 ]; then
		dialog --yesno "$DST_DEV is already partitioned. Are you sure you want to continue? (will be wiped out)" 40 120
		CONT=$?
		if [ $CONT -eq 1 ]; then
			echo "Exiting installer"
			exit
		fi
	fi
}
function remove_all_partitions {
	for v_partition in $(parted -s $DST_DEV print|awk '/^ / {print $1}')
	do
		parted -s $DST_DEV rm ${v_partition}
	done
}


############################################################
# Two partitions creation, mounting and unmounting functions
############################################################

# Gets three parameters. Size of first partition in MB, filesystem type of first and second partition
function create_two_partitions {
	if [ $DST_DEV == "/dev/mmcblk0" ]; then
		FIRST_PART="/dev/mmcblk0p1"
		SECOND_PART="/dev/mmcblk0p2"
	fi
	v_disk=$(parted -s $DST_DEV unit MB print|awk '/^Disk/ {print $3}'|sed 's/[Mm][Bb]//')
	v_part1=`expr 1 + $1`
	parted -s $DST_DEV mkpart primary $2 1 ${v_part1}MB
	parted -s $DST_DEV mkpart primary $3 ${v_part1}MB ${v_disk}MB
	sync
	if [ $2 == "fat32" ]; then
		mkdosfs $FIRST_PART
	else
		mkfs.$2 $FIRST_PART
	fi
	if [ $3 == "fat32" ]; then
		mkdosfs $SECOND_PART
	else
		mkfs.$3 $SECOND_PART
	fi
}
function mount_on_top {
	mkdir -p /tmp/part
	mount $SECOND_PART /tmp/part
	mkdir -p /tmp/part/boot
	mount $FIRST_PART /tmp/part/boot
	ROOTFS_DIR="/tmp/part"
}

function umount_on_top {
	umount /tmp/part/boot
	umount /tmp/part/
}


###########################################################
# One partition creation, mounting and unmounting functions
###########################################################

# Gets one parameter - Filesystem type
# For example - create_two_parts 200 ext2 ext4
function create_one_partition {
	if [ $DST_DEV == "/dev/mmcblk0" ]; then
		FIRST_PART="/dev/mmcblk0p1"
	fi
	v_disk=$(parted -s $DST_DEV unit MB print|awk '/^Disk/ {print $3}'|sed 's/[Mm][Bb]//')
	parted -s $DST_DEV mkpart primary $1 1 ${v_disk}MB
	sync
	if [ $1 == "fat32" ]; then
		mkdosfs $FIRST_PART
	else
		mkfs.$1 $FIRST_PART
	fi
}

# Mounts first partition. Can accept a single parameter that has all the mount options
function mount_partition {
	mkdir -p /tmp/part
	if [ "x$1" == "x" ]; then
		mount $FIRST_PART /tmp/part
	else
		mount $FIRST_PART /tmp/part $1
	fi
	ROOTFS_DIR="/tmp/part"
}

function umount_partition {
	umount /tmp/part/
}


# Gets ntp date from network
function get_ntpdate {
	dialog --yesno "Update clock from the internet (pool.ntp.org)?" 40 120
	CONT=$?
	if [ $CONT -eq 0 ]; then
		killall -q ntpd
		ntpdate pool.ntp.org
		hwclock -w
	fi
}

###########################################################
# Main menu and it's loop
###########################################################

function main_menu {
	MSG="Please choose action"
	IP_ADDR=`ifconfig eth0 | grep inet`
	if [ "x$IP_ADDR" == "x" ]; then
		MSG="Please choose action (IP address not configured)"
	else
		MSG="Please choose action (IP addr $IP_ADDR)"
	fi
	dialog --menu "$MSG" 40 120 120 "1" "Obtain IP address from DHCP (on wired network)" "2" "Run the installer" "3" "Run installation script" "4" "Exit to shell" "5" "Reboot (remove USB stick first)" 2> $TMP
	CHOICE=`cat $TMP`
	if [ $CHOICE == "1" ]; then
		udhcpc -f -t 5 -n -q -S
		CONT=$?
		if [ $CONT -ne 0 ]; then
			dialog --msgbox "udhcpc (DHCP client) seem to have failed" 40 120
		fi
	udhcpc
	fi
	if [ $CHOICE == "2" ]; then
		get_destination
		get_distro_list
		wget -N --no-check-certificate ${VAR2[$PKG_IDX]}
		SCR_TO_SOURCE=`basename ${VAR2[$PKG_IDX]}`
		source $SCR_TO_SOURCE
		sync
		# If we are here. It means we are done. Start blinking the front LED
		echo timer > /sys/class/leds/cubox\:red\:health/trigger
	fi
	if [ $CHOICE == "3" ]; then
		get_destination
		dialog --inputbox "What is the local path of the script?" 40 120 2> $TMP
		SCR_TO_SOURCE=`cat $TMP`
		echo "Script to source $SCR_TO_SOURCE"
		source $SCR_TO_SOURCE
		sync
		# If we are here. It means we are done. Start blinking the front LED
		echo timer > /sys/class/leds/cubox\:red\:health/trigger
	fi

	if [ $CHOICE == "4" ]; then
		exit
	fi
	if [ $CHOICE == "5" ]; then
		# Is this dangerous? Maybe we should first check mounted volumes?
		sync
		reboot -f now
	fi
}

resize
#Disable screen blanking
echo -e '\033[9;0]\033[14;0]' > `tty`
while [ 1 ]; do
	main_menu
done
