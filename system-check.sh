#!/bin/bash


# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
PLAIN='\033[0m'
ORANGE='\033[38;5;202m'

# check root
[[ $EUID -ne 0 ]] && echo -e "${RED}Error:${PLAIN} This script must be run as root!" && exit 1

# install wget, fio and virt-what
if  [ ! -e '/usr/bin/wget' ] || [ ! -e '/usr/bin/fio' ] ||  [ ! -e '/usr/sbin/virt-what' ]
then
	echo -e "Installing packages..."
	echo -e "Please wait..."
	yum clean all > /dev/null 2>&1 && yum install -y epel-release > /dev/null 2>&1 && yum install -y wget fio virt-what > /dev/null 2>&1 
	apt-get update > /dev/null 2>&1 && apt-get install -y wget fio virt-what > /dev/null 2>&1
fi

# check if /scripts exists
if [ ! -d "/scripts" ];
then
	mkdir /scripts
fi

get_opsy() 
{
	[ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
	[ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
	[ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

calc_disk() 
{
	local total_size=0
	local array=$@
	for size in ${array[@]}
	do
		[ "${size}" == "0" ] && size_t=0 || size_t=`echo ${size:0:${#size}-1}`
		[ "`echo ${size:(-1)}`" == "M" ] && size=$( awk 'BEGIN{printf "%.1f", '$size_t' / 1024}' )
		[ "`echo ${size:(-1)}`" == "T" ] && size=$( awk 'BEGIN{printf "%.1f", '$size_t' * 1024}' )
		[ "`echo ${size:(-1)}`" == "G" ] && size=${size_t}
		total_size=$( awk 'BEGIN{printf "%.1f", '$total_size' + '$size'}' )
	done
	echo ${total_size}
}

next()
{
	printf "%-72s\n" "-" | sed 's/\s/-/g'
}

system_info ()
{
	clear
	print_logo
	virtua=$(virt-what)
	if [[ ${virtua} ]]; then
		virt="$virtua"
	else
		virt="No Virt"
	fi
	HOSTNAME=`hostname`
	IP=`curl -s https://ip.vinahost.vn`
	cname=$( awk -F: '/model name/ {name=$2} END {print name}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
	cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
	freq=$( awk -F: '/cpu MHz/ {freq=$2} END {print freq}' /proc/cpuinfo | sed 's/^[ \t]*//;s/[ \t]*$//' )
	tram=$( free -m | awk '/Mem/ {print $2}' )
	uram=$( free -m | awk '/Mem/ {print $3}' )
	swap=$( free -m | awk '/Swap/ {print $2}' )
	uswap=$( free -m | awk '/Swap/ {print $3}' )
	up=$( awk '{a=$1/86400;b=($1%86400)/3600;c=($1%3600)/60} {printf("%d days, %d hour %d min\n",a,b,c)}' /proc/uptime )
	load=$( w | head -1 | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//' )
	opsy=$( get_opsy )
	arch=$( uname -m )
	lbit=$( getconf LONG_BIT )
	kern=$( uname -r )
	date=$( date )
	disk_size1=($( LANG=C df -hPl | grep -wvE '\-|none|tmpfs|devtmpfs|by-uuid|chroot|Filesystem' | awk '{print $2}' ))
	disk_size2=($( LANG=C df -hPl | grep -wvE '\-|none|tmpfs|devtmpfs|by-uuid|chroot|Filesystem' | awk '{print $3}' ))
	disk_total_size=$( calc_disk ${disk_size1[@]} )
	disk_used_size=$( calc_disk ${disk_size2[@]} )
	echo "System Info"
	next
	echo "Hostname             : $HOSTNAME"
	echo "Primary IP           : $IP"
	echo "CPU model            : $cname"
	echo "Number of cores      : $cores"
	echo "CPU frequency        : $freq MHz"
	echo "Total size of Disk   : $disk_total_size GB ($disk_used_size GB Used)"
	echo "Total amount of Mem  : $tram MB ($uram MB Used)"
	echo "Total amount of Swap : $swap MB ($uswap MB Used)"
	echo "System uptime        : $up"
	echo "Load average         : $load"
	echo "OS                   : $opsy"
	echo "Arch                 : $arch ($lbit Bit)"
	echo "Kernel               : $kern"
	echo "Virt                 : $virt"
	echo "Date                 : $date"
	
	return 0
}

check_health ()
{
	clear
	print_logo
	echo "Disk(s) health"
	next
	echo > /scripts/bad-sector.txt
	if [ ! -f "/scripts/hdsentinel" ];
	then
		wget --no-check-certificate -O /scripts/hdsentinel https://upload.vina-host.com/vinahost/hdsentinel > /dev/null 2>&1
		chmod +x /scripts/hdsentinel
	fi
	/scripts/hdsentinel > /scripts/hdsentinel-result.txt
	cat /scripts/hdsentinel-result.txt | grep "/dev/" | cut -d":" -f2 | cut -d" " -f2 > /scripts/devices.txt
	cat /scripts/hdsentinel-result.txt | grep Health | cut -d":" -f2 | cut -d" " -f2 > /scripts/disk-health.txt
	cat /scripts/hdsentinel-result.txt | grep "PERFECT\|bad sector" > /scripts/sector.txt
	
	sed -i '/^$/d' /scripts/*.txt
	
	while read line
	do
		if echo $line | grep PERFECT > /dev/null 2>&1;
		then
			echo 0 >> /scripts/bad-sector.txt
		elif echo $line | grep "bad sector" > /dev/null 2>&1;
		then
			echo $line | grep -Po "[[:digit:]]+ *(?=bad sector)" >> /scripts/bad-sector.txt
		fi
	done < /scripts/sector.txt
	
	echo -e "device\t\t| health\t| bad sector\t"
	echo "--------------------------------------------"
	
	device_num=`cat /scripts/devices.txt | wc -l`
	i=1
	while [ $i -le $device_num ]
	do
		DEVICE=`awk "NR==$i" /scripts/devices.txt`
		HEALTH=`awk "NR==$i" /scripts/disk-health.txt`
		BAD_SECTOR=`awk "NR==$i" /scripts/bad-sector.txt`
		if [ $HEALTH == "Unknown" ];
		then
			echo -e "$DEVICE\t| $HEALTH\t| $BAD_SECTOR\t"
		else
			echo -e "$DEVICE\t| $HEALTH\t\t| $BAD_SECTOR\t"
		fi
		((i++))
	done
	
	rm -rf /scripts/devices.txt
	rm -rf /scripts/disk-health.txt
	rm -rf /scripts/sector.txt
	rm -rf /scripts/bad-sector.txt
	rm -rf /scripts/hdsentinel-result.txt
	
	return 0
}

check_mdadm ()
{
	# Check for failed disk
	if ! egrep "\[.*_.*\]" /proc/mdstat  > /dev/null
	then
		return 0 # healthy
	else
		cat /proc/mdstat
		return 1 # failed
	fi
}

check_zfs ()
{
	condition=$(/sbin/zpool status | egrep -w -i '(DEGRADED|FAULTED|OFFLINE|UNAVAIL|REMOVED|FAIL|DESTROYED|corrupt|cannot|unrecover)')
	if [ "${condition}" ]; 
	then
		/sbin/zpool status
		return 2 # HEALTH fault
	fi

	errors=$(/sbin/zpool status | grep ONLINE | grep -v state | awk '{print $3 $4 $5}' | grep -v 000)
	if [ "${errors}" ]; 
	then
		/sbin/zpool status
		return 3 # Drive Errors
	fi
	
	return 0 # healthy
}

check_ceph ()
{
	HEALTH=$(ceph health)
	ACTIONABLE_WARNINGS=$(ceph health detail | egrep 'backfill_toofull|incomplete')
	HEALTH_FILTERED=$(ceph health detail | egrep -v 'HEALTH_WARN|OBJECT_MISPLACED|PG_DEGRADED|backfilling|wait_backfill|backfill_wait|recover|noscrub|nodeep-scrub|failing to respond to cache pressure|noout|currently failed to')
	if [ "$HEALTH" != 'HEALTH_OK' ] && [ "$ACTIONABLE_WARNINGS" ]
	then
		echo "Ceph is not healthy:"
		ceph status
		echo "Note these PGs:"
		ceph health detail | egrep 'backfill_toofull|incomplete'
		return 1
	elif [ "$HEALTH" != 'HEALTH_OK' ] && [ "$HEALTH_FILTERED" ]
	then
		echo "Ceph is not healthy:"
		ceph status
		return 1
	fi
	
	return 0 # healthy
}

check_raid ()
{
	clear
	print_logo
	echo "RAID check"
	next
	MDADM=`df -h | grep "/md" | wc -l`
	ZFS=`mount | grep zfs | wc -l`
	CEPH=`mount | grep ceph | wc -l`

	if [ $MDADM -ge 1 ];
	then
		echo "MDADM detected"
		check_mdadm
		print_result $?
	fi
		
	if [ $ZFS -ge 1 ];
	then
		echo "ZFS detected"
		check_zfs
		print_result $?
	fi

	if [ $CEPH -ge 1 ];
	then
		echo "Ceph detected"
		check_ceph
		print_result $?
	fi
	
	if [ $MDADM -lt 1 ] && [ $ZFS -lt 1 ] && [ $CEPH -lt 1 ];
	then
		echo "System is using hard RAID or no RAID configured"
	fi
	
	return 0
}

io_test() 
{
    (LANG=C dd if=/dev/zero of=test_$$ bs=64k count=16k conv=fdatasync && rm -f test_$$ ) 2>&1 | awk -F, '{io=$NF} END { print io}' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

dd_test() 
{
	echo "dd Test"
	io1=$( io_test )
	echo "I/O (1st run)        : $io1"
	io2=$( io_test )
	echo "I/O (2nd run)        : $io2"
	io3=$( io_test )
	echo "I/O (3rd run)        : $io3"
	ioraw1=$( echo $io1 | awk 'NR==1 {print $1}' )
	[ "`echo $io1 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw1=$( awk 'BEGIN{print '$ioraw1' * 1024}' )
	ioraw2=$( echo $io2 | awk 'NR==1 {print $1}' )
	[ "`echo $io2 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw2=$( awk 'BEGIN{print '$ioraw2' * 1024}' )
	ioraw3=$( echo $io3 | awk 'NR==1 {print $1}' )
	[ "`echo $io3 | awk 'NR==1 {print $2}'`" == "GB/s" ] && ioraw3=$( awk 'BEGIN{print '$ioraw3' * 1024}' )
	ioall=$( awk 'BEGIN{print '$ioraw1' + '$ioraw2' + '$ioraw3'}' )
	ioavg=$( awk 'BEGIN{printf "%.1f", '$ioall' / 3}' )
	echo "Average              : $ioavg MB/s"
}

fio_test() 
{
	if [ -e '/usr/bin/fio' ]; then
		echo "Fio Test"
		local tmp=$(mktemp)
		fio --randrepeat=1 --ioengine=libaio --direct=1 --gtod_reduce=1 --name=fio_test --filename=fio_test --bs=4k --numjobs=1 --iodepth=64 --size=256M --readwrite=randrw --rwmixread=75 --runtime=30 --time_based --output="$tmp"  > /dev/null 2>&1
		
		if [ $(fio -v | cut -d '.' -f 1) == "fio-2" ]; then
			local iops_read=`grep "iops=" "$tmp" | grep read | awk -F[=,]+ '{print $6}'`
			local iops_write=`grep "iops=" "$tmp" | grep write | awk -F[=,]+ '{print $6}'`
			local bw_read=`grep "bw=" "$tmp" | grep read | awk -F[=,B]+ '{if(match($4, /[0-9]+K$/)) {printf("%.1f", int($4)/1024);} else if(match($4, /[0-9]+M$/)) {printf("%.1f", substr($4, 0, length($4)-1))} else {printf("%.1f", int($4)/1024/1024);}}'`"MB/s"
			local bw_write=`grep "bw=" "$tmp" | grep write | awk -F[=,B]+ '{if(match($4, /[0-9]+K$/)) {printf("%.1f", int($4)/1024);} else if(match($4, /[0-9]+M$/)) {printf("%.1f", substr($4, 0, length($4)-1))} else {printf("%.1f", int($4)/1024/1024);}}'`"MB/s"
			
		elif [ $(fio -v | cut -d '.' -f 1) == "fio-3" ]; then
			local iops_read=`grep "IOPS=" "$tmp" | grep read | awk -F[=,]+ '{print $2}'`
			local iops_write=`grep "IOPS=" "$tmp" | grep write | awk -F[=,]+ '{print $2}'`
			local bw_read=`grep "bw=" "$tmp" | grep READ | awk -F"[()]" '{print $2}'`
			local bw_write=`grep "bw=" "$tmp" | grep WRITE | awk -F"[()]" '{print $2}'`
		fi

		echo "Read performance     : $bw_read"
		echo "Read IOPS            : $iops_read"
		echo "Write performance    : $bw_write"
		echo "Write IOPS           : $iops_write"
		
		rm -f $tmp fio_test
	else
		echo "Fio is missing!!! Please install Fio before running test."
	fi
}

diskio_test ()
{
	clear
	print_logo
	echo "Disk IO speed test"
	next
	cores=$( awk -F: '/model name/ {core++} END {print core}' /proc/cpuinfo )
	dd_test
	echo "-----------------------------------"
	fio_test $cores
	return 0
}

speed_test() 
{
	local speedtest=$(wget -4O /dev/null -T300 $1 2>&1 | awk '/\/dev\/null/ {speed=$3 $4} END {gsub(/\(|\)/,"",speed); print speed}')
	local ipaddress=$(ping -c1 -4 -n `awk -F'/' '{print $3}' <<< $1` | awk -F'[()]' '{print $2;exit}')
	local nodeName=$2
	printf "${YELLOW}%-40s${GREEN}%-16s${RED}%-14s${PLAIN}\n" "${nodeName}" "${ipaddress}" "${speedtest}"
}

network_test ()
{
	clear
	print_logo
	echo "Network speed test"
	next
	case $1 in
	1)
		speed_test 'http://speedtest1.vtn.com.vn/speedtest/random4000x4000.jpg' 'VNPT, Ha Noi, VN'
		speed_test 'http://speedtest3.vtn.com.vn/speedtest/random4000x4000.jpg' 'VNPT, Ho Chi Minh, VN'
		speed_test 'http://speedtestkv1a.viettel.vn/speedtest/random4000x4000.jpg' 'Viettel Network, Ha Noi, VN'
		speed_test 'http://speedtestkv3a.viettel.vn/speedtest/random4000x4000.jpg' 'Viettel Network, Ho Chi Minh, VN'
		speed_test 'http://speedtesthn.fpt.vn/speedtest/random4000x4000.jpg' 'FPT Telecom, Ha Noi, VN'
		speed_test 'http://speedtest.fpt.vn/speedtest/random4000x4000.jpg' 'FPT Telecom, Ho Chi Minh, VN'
		speed_test 'https://lax-ca-us-ping.vultr.com/vultr.com.100MB.bin' 'USA'
		speed_test 'http://speedtest.singapore.linode.com/100MB-singapore.bin' 'Singapore'
		speed_test 'http://speedtest.hkg02.softlayer.com/downloads/test100.zip' 'Hongkong'
		speed_test 'http://speedtest.tokyo2.linode.com/100MB-tokyo.bin' 'Japan'
		;;
	2)
		speed_test 'http://speedtest1.vtn.com.vn/speedtest/random4000x4000.jpg' 'VNPT, Ha Noi, VN'
		;;
	3)
		speed_test 'http://speedtest3.vtn.com.vn/speedtest/random4000x4000.jpg' 'VNPT, Ho Chi Minh, VN'
		;;
	4)
		speed_test 'http://speedtestkv1a.viettel.vn/speedtest/random4000x4000.jpg' 'Viettel Network, Ha Noi, VN'
		;;
	5)
		speed_test 'http://speedtestkv3a.viettel.vn/speedtest/random4000x4000.jpg' 'Viettel Network, Ho Chi Minh, VN'
		;;
	6)
		speed_test 'http://speedtesthn.fpt.vn/speedtest/random4000x4000.jpg' 'FPT Telecom, Ha Noi, VN'
		;;
	7)
		speed_test 'http://speedtest.fpt.vn/speedtest/random4000x4000.jpg' 'FPT Telecom, Ho Chi Minh, VN'
		;;
	8)
		speed_test 'https://lax-ca-us-ping.vultr.com/vultr.com.100MB.bin' 'USA'
		;;
	9)
		speed_test 'http://speedtest.singapore.linode.com/100MB-singapore.bin' 'Singapore'
		;;
	10)
		speed_test 'http://speedtest.hkg02.softlayer.com/downloads/test100.zip' 'Hongkong'
		;;
	11)
		speed_test 'http://speedtest.tokyo2.linode.com/100MB-tokyo.bin' 'Japan'
		;;
	esac
	
	return 0
}

print_menu ()
{
	print_logo
	echo -e "1) System info\t\t\t\t\t\t\t\t|"
	echo -e "2) Check disk(s) health\t\t\t\t\t\t\t|"
	echo -e "3) Check RAID (mdadm, zfs, ceph)\t\t\t\t\t|"
	echo -e "4) Disk IO speed test\t\t\t\t\t\t\t|"
	echo -e "5) Network speed test\t\t\t\t\t\t\t|"
	echo -e "0) Exit\t\t\t\t\t\t\t\t\t|"
	next
}

print_speedtest_menu ()
{
	clear
	print_logo
	echo "1) All"
	echo "2) VNPT, Ha Noi, VN"
	echo "3) VNPT, Ho Chi Minh, VN"
	echo "4) Viettel Network, Ha Noi, VN"
	echo "5) Viettel Network, Ho Chi Minh, VN"
	echo "6) FPT Telecom, Ha Noi, VN"
	echo "7) FPT Telecom, Ho Chi Minh, VN"
	echo "8) USA"
	echo "9) Singapore"
	echo "10) HongKong"
	echo "11) Japan"
	echo "0) Exit"
	next
}

get_option ()
{
	opt=69
	while [ $opt -gt $1 ]
	do
		printf "Option: "
		read -r opt
		case $opt in
		''|*[!0-9]*) 
			echo "invalid option"
			opt=69
			;;
		*) 
			;;
		esac
	done
	return $opt
}

print_result ()
{
	case $1 in
	1)
		printf "Status: ${RED}ERROR${PLAIN}\n"
		;;
	2)
		printf "Status: ${RED}Health fault${PLAIN}\n"
		;;
	3)
		printf "Status: ${RED}Drive error${PLAIN}\n"
		;;
	0)
		printf "Status: ${GREEN}Healthy${PLAIN}\n"
		;;
	esac
	echo ""
}

main ()
{
	opt=69
	while [ ! $opt -eq 0 ]
	do
		clear
		print_menu
		get_option 5
		opt=$?
		case $opt in
		1)
			system_info
			;;
		2)
			check_health
			;;
		3)
			check_raid
			;;
		4)
			diskio_test
			;;
		5)
			again="y"
			while [ $again == "y" ]
			do
				print_speedtest_menu
				get_option 10
				net_opt=$?
				if [ $net_opt -ne 0 ];
				then
					network_test $net_opt
					printf "Try again with another host? (y for YES): "
					read -r again
					re='[a-zA-Z]'
					if [[ "$again" =~ $re ]]; then
						case $again in
						y)
							;;
						Y)
							again="y"
							;;
						*)
							again="n"
							;;
						esac
					else 
						again="n"
					fi
				else
					again="n"
				fi			
			done
			opt=69
			;;
		0)
			echo "Exit"
			return 0
			;;
		esac
		next
		printf "Press [Enter] to back to Main menu..."
		read
	done
}

clear
main
