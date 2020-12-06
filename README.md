# raspisms-gammu-reliable-service
Autonomous USB modem reset for gammu-smsd and raspisms reliable service

## Context

[RaspiSMS](https://github.com/RaspbianFrance/raspisms) proposes a simple and intuitive web interface to read/write SMS through a gammu supported device on a raspberry pi. Having a spare ZTE MF112 which seems to be fully compatible according to https://wammu.eu/phones/zte, I've properly configured the system.

![Compatible usb mobile broadband device](/images/zte-mf112-wammu.png)

After some light testing: 
* Receiving several text messages properly works
* Sending several text messages properly works
* Sending one text message does no longer allow to receive any text message

Some examples of log error you can encounter:
```
gammu-smsd-log.1:Sun 2020/11/29 23:45:50 gammu-smsd[86797]: Terminating communication: No response in specified timeout. Probably the phone is not connected. (TIMEOUT[14])
gammu-smsd-log.1:Sun 2020/11/29 23:45:50 gammu-smsd[86797]: Going to 30 seconds sleep because of too many connection errors
gammu-smsd-log.1:Sun 2020/11/29 23:46:20 gammu-smsd[86797]: Starting phone communication...
gammu-smsd-log.1:Sun 2020/11/29 23:46:20 gammu-smsd[86797]: Can't open device: Error opening device. Unknown, busy or no permissions. (DEVICEOPENERROR[2])
gammu-smsd-log.1:Sun 2020/11/29 23:46:20 gammu-smsd[86797]: Stopping Gammu smsd: No error. (NONE[1])
gammu-smsd-log.1:Sat 2020/12/05 22:13:43 gammu-smsd[229431]: Error getting SMS: Invalid location. Maybe too high? (INVALIDLOCATION[24])
gammu-smsd-log.1:Sat 2020/12/05 22:13:57 gammu-smsd[229431]: Ignoring incoming SMS info as not a Status Report in SR memory.
gammu-smsd-log.1:Sat 2020/12/05 22:26:34 gammu-smsd[230025]: Error getting security status: Can not access SIM card. (NOSIM[49])
gammu-smsd-log.1:Sat 2020/12/05 22:26:34 gammu-smsd[230025]: You might want to set CheckSecurity = 0 to avoid checking security status
gammu-smsd-log.1:Sat 2020/12/05 22:26:34 gammu-smsd[230025]: Already hit 0 errors
gammu-smsd-log.1:Sat 2020/12/05 22:26:34 gammu-smsd[230025]: Terminating communication: No error. (NONE[1])
```

A hard reboot allows to recover the situation at the cost of several minutes of downtime. 

In the following, we describe the config in place to provide a reliable SMS service. There are custom recovery scripts to manage the gammu-smsd service, the usb mobile broadband modem, and an sms2mail gateway.

## Architecture

![Architecture with RaspiSMS, Gammu-smsd, SSMTP and the scripts to restart usb device if needed](/images/architecture-raspisms-gammu-reliable.png)

The flow is
1. SMS are received by the device and transmitted to RaspiSMS through the gammu-smsd service
2. RaspiSMS regularly
  * Receive SMS and forward the SMS through SSMTP
  * Send scheduled SMS
3. The reliable service regularly check for errors. In case of error, it resets the USB modem device

## Configuration

### Gammu-smsd

```
# Configuration file for Gammu SMS Daemon

# Gammu library configuration, see gammurc(5)
[gammu]
device = /dev/ttyUSB1
name = Phone on USB serial port ZTE_Incorporated ZTE_WCDMA_Technologies_MSM
connection = at
# Debugging
#LogFormat = textalldate
#LogFile = gammulog

# SMSD configuration, see gammu-smsdrc(5)
[smsd]
service = files
logfile = /var/log/gammu-smsd-log
RunOnReceive = /var/www/html/RaspiSMS/parseSMS.sh
# Increase for debugging information
#debuglevel = 255
debuglevel = 0
# Paths where messages are stored
inboxpath = /var/spool/gammu/inbox/
outboxpath = /var/spool/gammu/outbox/
sentsmspath = /var/spool/gammu/sent/
errorsmspath = /var/spool/gammu/error/
```

If you'd like to test your configuration. For gammu cmd line, please ensure first that `gammu-smsd` service is stopped. Otherwise you might end up with busy device accesses.
```sh
gammu --identify
gammu-smsd-inject TEXT 06XXXXXX -text "Hello from rpi smsd inject" 
gammu sendsms TEXT 06XXXXXXX -text "Hello from rpi"
gammu getsecuritystatus
```

If you'd like to directly test some AT commands on your device:
```sh
  echo -e "AT+CMGF=1\r" > /dev/ttyUSB1
  echo -e "AT+CMGD=1,4\r" > /dev/ttyUSB1
  echo -e "AT+CMGL=?\r" > /dev/ttyUSB1
```

### RaspiSMS

Few modifications on RaspiSMS installation. Instead of relying on their integration of mail notification, I send an email immediately through local mail agent.

```bash
# cat /var/www/html/RaspiSMS/parseSMS.sh
#!/bin/bash
date=$(date +%Y%m%d%H%M%S%N)
first_time=1
for i in `seq $SMS_MESSAGES` ; do
        eval "sms_number=\"\${SMS_${i}_NUMBER}\""
        eval "sms_text=\"\${SMS_${i}_TEXT}\""
        if [ $first_time -eq 1 ]
        then
                sms="$sms_number:"
                first_time=0
        fi
        sms="$sms$sms_text"
done
echo "$sms" >> /var/www/html/RaspiSMS/receiveds/"$date".txt

#GBY20201112: Direct notification per mail
echo -e "To: recipient@domain.tld\nFrom: sender@domain.tld\nSubject: Transfert d'un sms de ${sms_number}\n\n${sms}" | ssmtp recipient@domain.tld
```

### SSMTP

There is few to say. One can follow https://wiki.archlinux.org/index.php/SSMTP to have a simple catchall mail redirection service. 

### Reliable service
It consists of a crontab bash script. The script verify errors and reset USB device if needed.

```
# crontab -l
* * * * * /usr/bin/flock -w 0 /var/run/gammu-smsd-last-check.lock /home/ubuntu/usbreset.bash >> /var/log/gammu-smsd-last-check.log
```

The interessting part is how to actually reset USB device. Several possibilities, but only one was effective on (my) RPI3. Code taken from https://raspberrypi.stackexchange.com/questions/6782/commands-to-simulate-removing-and-re-inserting-a-usb-peripheral.

Some others were triggering some panics or not working at all. 
```sh
echo '1-1' > /sys/bus/usb/drivers/usb/unbind
echo '1-1' > /sys/bus/usb/drivers/usb/bind
sudo usb_modeswitch -v 0x7392 -p 0x7811 --reset-usb
```
