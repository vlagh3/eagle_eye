#!/bin/bash
#	 ___________	
#   |.---------.|		Contact
#   ||         ||		-------
#   || JellyPi ||			Website:	
#   ||         ||			Gitlab : https://gitlab.com/JellyPi101
#   |'---------'|
#	`._________.'		Description
#	   |	 |			-----------
#	  /		  \				
#   .-		   -.  			
#  /		 	 \ 			Options 
#  |			 |				
#  |			 |				
#  |			 |
#  |			 |



#### FUNCTIONS ####

function usage() {
	printf "  Usage: $script_name <options>\n\t-i -- Show system information\n\t-u -- Show usage (cpu, hard disk partitions)\n\t-s -- Show status of the provided services. Services need to be separated by a comma and without spaces (e.g: nginx,tor,sshd,mongodb)\n\t-t -- Show temperatures (CPU Cores, Partitions)\n\t-p -- Show processes\n"
}

# This function displays a basic overview of your system
# such as: Distribution, kernel version, processes, memory, etc
function display_system_info() {
	# Distro
	distro=$(cat /etc/*release | grep PRETTY_NAME | cut -d "=" -f 2- | sed 's/"//g')

	# Kernel
	kernel=$(uname -sr)

	# Uptime
	uptime=$(uptime -p)

	# Load
	load=`cat /proc/loadavg | awk '{ print $1,$2,$3,$5 }'`

	# Processes
	procs=`ps -eo user | sort | uniq -c | awk '{print $2 " " $1}'`
	proc_root=`echo "$procs" | grep root | awk '{print $2}'`
	proc_user=`echo "$procs" | grep -v root | awk '{print $2}' | awk '{ SUM += $1} END { print SUM }'`
	proc_all=`echo "$procs" | awk '{print $2}' | awk '{ SUM += $1} END { print SUM }'`

	# CPU
	CPU=`grep "model name" /proc/cpuinfo | cut -d ' ' -f3- | head -1`

	# Memory
	IFS=" " read total used free <<<$(free -htm | grep "Mem" | awk {'print $3,$4,$2'})

	echo -e "${BOLD}${YELLOW}system info:${RST}\n
  Distro....:	$distro
  Uptime....:	$uptime
  Kernel....:	$kernel

  Load......:	$load
  Processes.:	${GREEN}$proc_all${RST} (total)	${GREEN}$proc_root${RST} (root)	${GREEN}$proc_user${RST} (user)

  Memory....:	${GREEN}$total${RST} (total)	${GREEN}$used${RST} (used)	${GREEN}$free${RST} (free)
  CPU.......:	$CPU\n"
}


function hard_usage() {

	# disk usage: ignore zfs, squashfs & tmpfs
	mapfile -t dfs < <(df -H -x zfs -x squashfs -x tmpfs -x devtmpfs -x overlay --output=target,pcent,size | tail -n+2)

	for line in "${dfs[@]}"; do
		# get disk usage
		usage=$(echo "$line" | awk '{print $2}' | sed 's/%//')
		used_width=$((($usage*$bar_width)/100))
		# color is green if usage < max_usage, else red
		if [ "${usage}" -ge "${max_usage}" ]; then
			color=$RED
		else
			color=$GREEN
		fi
		# print green/red bar until used_width
		bar="[${color}"
		for ((i=0; i<$used_width; i++)); do
			bar+="="
		done
		# print dimmmed bar until end
		bar+="${WHITE}${dim}"
		for ((i=$used_width; i<$bar_width; i++)); do
			bar+="="
		done
		bar+="${undim}]"
		# print usage line & bar
		echo "${line}" | awk '{ printf("%-31s%+3s used out of %+4s\n", $1, $2, $3); }' | sed -e 's/^/  /'
		echo -e "${bar}" | sed -e 's/^/  /'
	done
}

function cpu_usage() {
  # 0 1:user 2:unice 3:sys 4:idle 5:iowait 6:irq 7:softirq 8:steal 9:guest 10:?
  ncpu=($(head -1</proc/stat))
  sum="${ncpu[@]:1:5}"

  cpu_total=$((${sum// /+}))
  cpu_maxval=$((cpu_total - ocpu_total))
  cpu_val=$((cpu_maxval - (ncpu[4]-ocpu[4])))
  cpu_percentage=$((100 * cpu_val / cpu_maxval))

  ocpu=("${ncpu[@]}")
  ocpu_total=$cpu_total

  printf -v bar "  %$((($(tput cols) - 5) * cpu_percentage / 100))s" ""
  printf ' %3d%% %s\n' "$cpu_percentage" "${bar// /█}"
}

function show_usage() {
	echo -e "${BOLD}${YELLOW}usage:${RST}\n"

	# Thanks god you are a living human being ( https://github.com/yboetz/motd/blob/master/35-diskspace )
	hard_usage

	# CPU ( kuddos to this guy https://blog.yjl.im/2010/12/cpu-utilization-calculation-in-bash.html )
	echo -e "\n   ${GREEN}CPU${RST}"
	cpu_usage
	echo -e "\n"
}


function check_service() {
	# Inactive
	if [ $(systemctl is-active $1) == "inactive" ]; then 
		[ "$2" == "1" ] && printf "  $1:\t${RED}  inactive ${RST}\n"
		[ "$2" == "1" ] || printf "  $1:\t${RED}  inactive ${RST}\t"
	# Active
	else
		[ "$2" == "1" ] && printf "  $1:\t${GREEN}  active ${RST}\n"
		[ "$2" == "1" ] || printf "  $1:\t${GREEN}  active ${RST}\t"
	fi
}

function show_services() {
	# Check every service status from the config file
	echo -e "${BOLD}${YELLOW}services:${RST}\n"
	count=0
	for service in "${services_arr[@]}"; do
		if !(( count % 2 )); then
			check_service $service
		else
			check_service $service 1
		fi
		((count++))
	done
	echo -e "\n"
}


function show_hard_temp(){

	# Check what format (nvme, sda)
	hard_type="$(lsblk | awk '{print $1}' | sed "2q;d")"

	# Get number of partitions
	total_part=$(cat /proc/partitions | awk '{print $2}' | sed "7q;d")

	# If nvme use nvme cmd utility
	if [[ $hard_type == *"nvme"* ]]; then
		for i in $(eval echo "{1..$total_part}");do
			hpart="${hard_type}p$i"
			htemp=$(nvme smart-log /dev/$hpart | grep "^temperature" | awk '{print $3}')

			# Choose color based on temperature
			color=`tput setab 2`	# Green
			[ $htemp -gt "34" ] && color=`tput setab 1`	# Red
			[ $htemp -gt "30" ] && color=`tput setab 3`	# Yellow

			# Print 2 partitons per line
			if (( i % 2 )); then
				printf "  ${color}$hpart: $htemp°C${RST}\t\t"
			else
				printf "  ${color}$hpart: $htemp°C${RST}\n"
			fi
		done
	# Else use hddtemp (TODO)
	fi
}

function show_temperature() {
	echo -e "${BOLD}${YELLOW}temperatures${RST}\n"
	core_nr=""
	count=0
	while read -r core; do

		# Retrieve core number and temperature
		core_nr="$(echo -e $core | awk '{print $2}')"
		temp="$(echo -e $core | awk '{print $3}' | sed -e 's/..$//' | cut -c2-)"

		# Set color based on temperature
		color=`tput setab 2`	# Green
		[ "$(echo -e "$temp" | sed -e 's/..$//')" -gt "50" ] && color=`tput setab 1`	# Red
		[ "$(echo -e "$temp" | sed -e 's/..$//')" -gt "48" ] && color=`tput setab 3`	# Yellow

		# Set format based on the number of the core
		if [ "$count" -eq "1" ]; then
			printf "  ${color}${BLACK}CORE $core_nr $temp °C${RST}\n"
		else
			printf "  ${color}${BLACK}CORE $core_nr $temp °C${RST}\t\t"
		fi

		((count+=1))

	done <<< $(sensors | grep Core | awk '{print $1,$2,$3}' )
	echo -e "\n"

	show_hard_temp
}

#### GLOBAL VARIABLES ####

# Colors
RST=`tput sgr0`
RED=`tput setaf 1`
BOLD=`tput bold`
GREEN=`tput setaf 2`
BLACK=`tput setaf 0`
WHITE=`tput setaf 7`
YELLOW=`tput setaf 3`
dim="\e[2m"
undim="\e[0m"

# Bools
sprocs=0
snet=0
susage=0
sinfo=0
stemp=0
services_arr=(nginx sshd tor mongodb)
services=""

# Config
script_name=$0
no_args=1
max_usage=90
bar_width=50

# Main
#	-p -- show procs
#	-n -- network
#	-u -- usage (cpu, hard)
#	-t -- temperature
#	-i -- sys info
#	-s -- services
#	
#	Default everything is turned on and services are: nginx, sshd, tor, mongodb


# stat -p (shows only procs)


# Check if script is ran as root
[ "$EUID" -ne 0 ] && echo "${BOLD}${RED}This script needs to be executed by root${RST}" && exit 1

while getopts ":pnuits:h" opts; do
	case "${opts}" in
		p) sprocs=1;;
		n) snet=1;;
		u) susage=1;;
		i) sinfo=1;;
		s) services=${OPTARG};;
		t) stemp=1;;
		h) usage && exit;;
		*) usage && exit;;
	esac
	no_args=0
done

[ $sinfo -eq 1 ] && display_system_info
[ $susage -eq 1 ] && show_usage
[ -n "$services" ] && read -ra services_arr <<< $(echo -e "$services" | tr "," " ") && show_services
[ $stemp -eq 1 ] && show_temperature
