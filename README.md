# oracle-remote-clone

perform a clone of rman backup using bash shell and python completely remotely
providing passwordless scp is enabled and the remote server is configured with
the same mount points. This will work with container and pluggables databases

gather the mount points to cleanup on the remote server

```python
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
```


perform the restore and recover remotely

```python
python << EOF
import os, re
script = []
script.append('export ORACLE_SID=clrg')
script.append('sqlplus /nolog <<EOF')
script.append('create spfile from pfile;')
script.append('connect / as sysdba')
script.append('startup nomount')
script.append('EOF')
script.append('rman TARGET / NOCATALOG <<EOF')
entries = os.listdir('/store1/orabkup/clrg')
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
```
