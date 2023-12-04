txtblk='\e[0;30m' # Black - Regular
txtred='\e[0;31m' # Red
txtgrn='\e[0;32m' # Green
txtylw='\e[0;33m' # Yellow
txtblu='\e[0;34m' # Blue
txtpur='\e[0;35m' # Purple
txtcyn='\e[0;36m' # Cyan
txtwht='\e[0;37m' # White
txtnc="$(tput sgr0)" # No color
txtbold="$(tput bold)" # Bold
txtiton="$(tput sitm)" # Italic ON
txtitoff="$(tput ritm)" # Italic OFF

current_date_time="`date +%Y%m%d-%H%M`"
dump_file_name=~/zabbix_dumps/dbdump_zabbix_[$current_date_time].sql
arch_file_name=~/zabbix_dumps/dbdump_zabbix_[$current_date_time].7z
#printf "${txtylw}Creating mysql dump to file: ${txtbold}%s${txtnc}\n" $dump_file_name

printf "${txtpur}Stopping zabbix-server...${txtnc}\n" $dump_file_name
systemctl stop zabbix-server

printf "${txtylw}Creating dump to file: ${txtbold}${txtiton}%s${txtnc}\n" $dump_file_name
mysqldump zabbix > $dump_file_name

printf "${txtcyn}Restarting daemons...${txtnc}\n"
systemctl restart nginx && systemctl restart mysqld && systemctl restart zabbix-server

printf "${txtylw}Compressing dump file: ${txtbold}%s${txtnc}\n" $arch_file_name
7z a -sdel "$arch_file_name" "$dump_file_name"

echo "${txtnc}---"