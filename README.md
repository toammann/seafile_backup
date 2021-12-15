# seafile_backup

Run the backup with "/mnt/ext_backup/seaf_backup" as output folder
```
 ./backup-seafile.sh /mnt/ext_backup/seaf_backup        
```

The script will ask you for your private key to make ssh connections to the remote server. It will stop the seafile and seahub.

The next step is to backup the mysql databases. Enter the password of the myql root user to enable the script to create database dumps.

The output should look like this:

```
~/git/seafile_backup    main !2 ?1  ./backup-seafile.sh /mnt/ext_backup/seaf_backup

Check seahub service status
seahub systemd service is active. Stopping the service...
seahub successfully stopped
Check seafile service status
seafile systemd service is active. Stopping the service...
seafile successfully stopped
Create MySQL dumps. Enter password for the MYSQL root user
Enter password: 
Shared connection to seafile.ammanncloud.de closed.
    MySQL dump ccnet-db.sql
    MySQL dump seafile-db.sql
    MySQL seahub ccnet-db.sql

...

2-15 22:02:39 gc-core.c(392): GC deleted repo 4cb7c7b1.
2021-12-15 22:02:39 gc-core.c(392): GC deleted repo 132302e1.
2021-12-15 22:02:39 gc-core.c(392): GC deleted repo 0234dc97.
2021-12-15 22:02:39 gc-core.c(456): === GC is finished ===
seafserv-gc run done

Done.
Transfer seafile data folder
          2.45G   3%    5.89MB/s    0:06:37 (xfr#1515, to-chk=0/93842)   
Starting verify of data...
Verify of seafile data directory successful!
Start seafile service
seafile successfully started
Start seahub service
seahub successfully started
Backup sucessfully finished!
```