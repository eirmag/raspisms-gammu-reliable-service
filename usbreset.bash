#! /bin/bash
#GBY 2020-12-05
#rpisms script orchestrating the usb reset on the connected gsm device
#the reset is needed if there are two many errors in gammu-smsd
#errors are detected if gammu-smsd log file as errors since last check
#reset do perform several steps
#- stop gammu-smsd service
#- usbreset
#- verify device is properly responding
#- restart gammu-smsd service
#
#This script should be launched by crontab with flock locking
#
#Error detecting is performed by awk

LAST_CHECK_F=/var/run/gammu-smsd-last-check.ts
GAMMU_LOG_F=/var/log/gammu-smsd-log
GAWK_F=/home/ubuntu/gawk.awk
USB_RESET=/home/ubuntu/a.out

stop_service(){
	systemctl status gammu-smsd > /dev/null 2>&1 
	if [ $? -eq 0 ]
	then
		systemctl stop gammu-smsd
	else
		echo "Already stopped"
	fi
}

usbreset(){
	DEVNUMS=`lsusb | grep -i sms | tr -d : | awk '{print "/dev/bus/usb/" $2 "/" $4}'`	
	for i in $DEVNUMS; do
		echo -e "\tReset $i"
		$USB_RESET $i
	done;
	echo -e "\tSleep 5"
	sleep 5
}

check_device_responding(){
	gammu --identify
	if [[ $? -ne 0 ]]
	then
		echo -e "\tDevice not responding!"
		exit 1
	fi
	echo -e "\tVerify security status"
	gammu getsecuritystatus
}

start_service(){
	systemctl start gammu-smsd
}

#0 if no error, 1 if in error
log_in_error(){
	local refdate=$1

	echo $refdate
	awk -v refdate=$refdate -f $GAWK_F $GAMMU_LOG_F

	return $?

}

set_lastrefdate(){
	local lastdate=$(date +%s)
	echo $lastdate > $LAST_CHECK_F
	echo -e "\t$(date -d@$lastdate) written in $LAST_CHECK_F"
}

get_lastrefdate(){
	local refdate
	if [[ -e $LAST_CHECK_F && -f $LAST_CHECK_F && -s $LAST_CHECK_F ]]
	then
		refdate=$(cat $LAST_CHECK_F)
	else
		refdate=$(date +"%s")
		set_lastrefdate
	fi
	echo $refdate
}

refdate=$(get_lastrefdate)
log_in_error $refdate
if [  $? -ne 0 ]
then
	echo "Log in error since $(date -d@$refdate)"
	echo "-- Stopping service --"
	stop_service
	echo "-- Resetting usb device --"
	usbreset
	echo "-- Checking device responds --"
	check_device_responding
	echo "-- Updating last execution run --"
	set_lastrefdate
	echo "-- Starting service --"
	start_service
else
	echo "Log not in error since $(date -d@$refdate)"
	echo "-- Starting service --"
	start_service
fi 

