#!/bin/bash
source $HOME/.bash_profile
#-------------------------------------------------------------------------
# Title      : clone.sh
# Author     : Spera Dennis <dennis.spera@uxDbx.com>
# Date       : 2021-01-26
# Category   : oracle database
# Requires   : oracle database software.
# SCCS-Id.   : 00.00.00.01
#-------------------------------------------------------------------------
#
# Description :
#
#     usage: rclone.sh -i instance -s server -d [YYYYMMDD]
#
#-------------------------------------------------------------------------
# prerequites:
#
# oracle 12+
# bash GNU bash, version 4.2.46(2)
# python 3.8+
#
#-------------------------------------------------------------------------
# to do:
#   make remote directories
#-------------------------------------------------------------------------
while getopts ":i:s:d:" opt; do
    case ${opt} in
      i  ) instance=$OPTARG ;;
      d  ) date=$OPTARG ;;
      s  ) server=$OPTARG ;;
      \? )
        echo "usage: rclone.sh -i instance -s server -d date"
        exit 1
        ;;
      : )
        echo "Invalid Option: -$OPTARG requires an argument" 1>&2
        exit 1
        ;;
    esac
done
shift $((OPTIND -1))

if [[ "${OPTIND}" -ne "7" ]]
then
        echo "usage: rclone.sh -i instance -s server -d date"
        exit 1
fi

export  timestamp=`date +%Y-%m-%d_%H-%M-%S`
export  log_file=clone_${timestamp}_.log
export  stage='/oradata/stage'
export  remote=$server
export  sid=$instance
export  stamp=$date
export  dbs='/app/oracle/app/oracle/product/12.2.0/dbhome_1/dbs'
exec > >(tee -a "$log_file") 2>&1

clear

function tag_step ()
{
echo "+----------------------------------------------------------------"
echo "|   $1"
echo "+----------------------------------------------------------------"

}

cd $scripts
tag_step "C L O N E "
#--------------------
# shutdown listener
#--------------------
tag_step "step 1.) shutdown listener"
ssh oracle@${remote} "source /home/oracle/.bash_profile; lsnrctl stop 1> /dev/null"

#---------------------
# shutdown instances
#---------------------
tag_step "step 2.) shutdown database"
ssh oracle@${remote} "source /home/oracle/.bash_profile; sh /app/scripts/shutdown.sh 1> /dev/null"

#-----------------------
# init old database
#-----------------------
tag_step "step 3.) cleanup database files"
python <<EOF
import os, re, cx_Oracle
import config as cfg

data = []

conn = cx_Oracle.connect(cfg.username, cfg.password, cfg.dsn, encoding=cfg.encoding)
print (conn)
curs = conn.cursor()
curs.arraysize = 50
curs.execute('select file_name from dba_data_files')
for file_name, in curs.fetchall():
    data.append(os.path.dirname(file_name))

curs.execute('select member FROM v\$logfile')
for file_name, in curs.fetchall():
    data.append(os.path.dirname(file_name))

curs.close()
conn.close()


data = list(dict.fromkeys(data))

f = open("${scripts}/remove.sh", "a")
for line in data:
    f.write('rm -f ' + line + '/*' + "\n")
    print ('rm -f ' + line + '/*')
f.close()

EOF

scp ${scripts}/remove.sh ${remote}:$stage
ssh oracle@${remote} "source /home/oracle/.bash_profile; sh ${stage}/remove.sh 2> /dev/null"

#-----------------------
# copy pieces to remote
#-----------------------
tag_step "step 4.) copy rman backup to remote server"
ssh ${remote} rm $stage/*
scp /store1/orabkup/${sid}/*${stamp}* ${remote}:$stage

#-------------------------------
# copy pfile from source to dest
#-------------------------------
tag_step "step 5.) copy init.ora to remote server"
scp ${dbs}/init${sid}.ora  ${remote}:${dbs}

#-------------------------------
# copy passwd from source to dest
#-------------------------------
tag_step "step 6.) copy orapw to remote server"
scp ${dbs}/orapw${sid}  ${remote}:${dbs}

#--------------------
# perform cloning
#--------------------
tag_step "step 7.) restore and recover"
rm start.sh

python << EOF
import os, re

script = []
script.append('export ORACLE_SID=${sid}')
script.append('sqlplus /nolog <<EOF')
script.append('create spfile from pfile;')
script.append('connect / as sysdba')
script.append('startup nomount')
script.append('EOF')

script.append('rman TARGET / NOCATALOG <<EOF')

entries = os.listdir('/store1/orabkup/${sid}')
for entry in entries:
    if (re.search(r"${stamp}",entry)) and (re.search(r"control",entry)):
       script.append("restore controlfile from '${stage}/" + entry + "';")
       script.append("sql 'alter database mount';")
       script.append("catalog start with '${stage}/' noprompt;")
       script.append("restore database;")
       script.append("recover database;")
       script.append("sql 'alter database open resetlogs';")
script.append('EOF')

f = open("${scripts}/start.sh", "a")
for line in script:
    print (line)
    f.write(line + "\n")
f.close()

EOF

scp start.sh ${remote}:$stage
ssh oracle@${remote} "source /home/oracle/.bash_profile; sh $stage/start.sh"


#--------------------
# cleanup
#--------------------
rm start.sh
rm remove.sh

