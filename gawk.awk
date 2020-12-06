#GBY 2020-12-05
#rpisms - errors from gammu-smsd logs because device is failing to properly respond

function month(mt){
	return (index("JanFebMarAprMayJunJulAugSepOctNovDec",mt)+2)/3
}

#Detect error or timeout. If there are more than 2, we exit with status code 1
/gammu-smsd/ && (/Error/ || /error/ || /timeout/) {
	if (gamerror > 2){
		exit(1)
	}
	split($3,time,":")
	split($2,months,"/")
	#below is relevant for entries starting with "Dec  5 00:01:01"
	#date = (strftime("%Y") " " month($1) " " $2 " " time[1] " " time[2] " " time[3])
	#below is relevant for entries starting with "Sun 2020/11/29 21:31:19"
	date = months[1] " " months[2] " " months[3]  " " time[1] " " time[2] " " time[3]
	if (mktime(date) > refdate){
		++gamerror
		print 
	}

	#print refdate, "'", date, "'", mktime(date), "1=", $1, "2=", $2, "3=", $3	
	
}
