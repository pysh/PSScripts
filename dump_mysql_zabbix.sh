txtblk='\e[0;30m' # Black - Regular
txtred='\e[0;31m' # Red
txtgrn='\e[0;32m' # Green
txtylw='\e[0;33m' # Yellow
txtblu='\e[0;34m' # Blue
txtpur='\e[0;35m' # Purple
txtcyn='\e[0;36m' # Cyan
txtwht='\e[0;37m' # White
txtnc="$(tput sgr0)" # No color
#txtnc='\033[0m' # No Color

current_date_time="`date +%Y%m%d-%H%M`"
dump_file_name=~/zabbix_dumps/dbdump_zabbix_[$current_date_time].sql
arch_file_name=~/zabbix_dumps/dbdump_zabbix_[$current_date_time].7z
#echo -e "${txtylw}Creating mysql dump: $dump_file_name${txtnc}"

echo -e "${txtpur}Stopping zabbix-server...${txtnc}"
systemctl stop zabbix-server
#systemctl stop zabbix-server && systemctl stop mysqld && systemctl stop nginx

echo -e "${txtylw}Waiting 5 sec...${txtnc}"
sleep 5

echo -e "${txtgrn}Creating dump file: $dump_file_name...${txtnc}"
mysqldump zabbix > $dump_file_name

echo -e "${txtylw}Waiting 5 sec...${txtnc}"
sleep 5

echo -e "${txtcyn}Starting zabbix-server...${txtnc}"
systemctl restart zabbix-server
#systemctl start nginx && systemctl start mysqld && systemctl start zabbix-server

echo -e "${txtylw}Compressing dump file: $dump_file_name => $arch_file_name${txtnc}"
7z a -sdel "$arch_file_name" "$dump_file_name"

echo "${txtnc}---"