#!/bin/bash
set -e
source backup-seafile.conf

#Colors
NOCOLOR='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'

# ============================================================================================================
# Functions ==================================================================================================
# ============================================================================================================

ssh_cmd(){
  ssh -o ControlPath=$SSH_CONTROL_PATH $SSH_HOST $1
  return $? #return exit code of the last cmd
}

mysql_dump(){

  #Create credentials file on host
  echo "Create MySQL dumps. Enter password for the mysql root user"

  ssh -t -o ControlPath=$SSH_CONTROL_PATH $SSH_HOST "mysql_config_editor set --login-path=backups --host=$MYSQL_HOST --user=$MYSQL_USER --password"

  echo "    MySQL dump ccnet-db.sql"
  ssh_cmd "mysqldump --login-path=backups --opt ccnet-db > $DIR_DB/`date +"%Y-%m-%d-%H-%M-%S"`_ccnet-db.sql" 
  
  echo "    MySQL dump seafile-db.sql"
  ssh_cmd "mysqldump --login-path=backups --opt seafile-db > $DIR_DB/`date +"%Y-%m-%d-%H-%M-%S"`_seafile-db.sql"
  
  echo "    MySQL seahub ccnet-db.sql"
  ssh_cmd "mysqldump --login-path=backups --opt seahub-db > $DIR_DB/`date +"%Y-%m-%d-%H-%M-%S"`_seahub-db.sql"

  #Remove login path
  ssh_cmd "mysql_config_editor remove  --login-path=backups"
}

stop_user_service(){

  echo "Check $1 service status"

  #Query State
  #STATE=$(ssh_cmd "systemctl --user is-active $1")
  STATE=$(ssh_cmd "systemctl --user show -p ActiveState $1 | cut -d'=' -f2")

  if [[ "$STATE" == "active" ]];then
  
    #Service is running -> Stop it
    echo "$1 systemd service is $STATE. Stopping the service..."
    ssh_cmd "systemctl --user stop $1" 

  else
    echo -e ""$GREEN"$1 not running. Status: $STATE"$NOCOLOR""
    return 0
  fi

  #Ensure that the service is stopped
  STATE=$(ssh_cmd "systemctl --user show -p ActiveState $1 | cut -d'=' -f2")

  if [[ "$STATE" == "inactive" ]];then

    echo -e ""$GREEN"$1 successfully stopped"$NOCOLOR""
    return 0
  fi

  echo -e ""$RED"$1 Error stopping service $1. Stopping the service resulted in ""$STATE"""$NOCOLOR"\n"
  return -1
}

start_user_service(){

  echo "Start $1 service"

  #Start attempt
  ssh_cmd "systemctl --user start $1" 

  #Query State
  STATE=$(ssh_cmd "systemctl --user show -p ActiveState $1 | cut -d'=' -f2")

  #Ensure that the service is started
  if [[ "$STATE" == "active" ]];then

    echo -e ""$GREEN"$1 successfully started"$NOCOLOR""
    return 0
  fi

  echo -e ""$RED"$1 Error starting service $1. Staring the service resulted in ""$STATE"""$NOCOLOR"\n"
  return -1
}

# ============================================================================================================
# Start of script ============================================================================================
# ============================================================================================================
{
  #try to to create output directiory if it does not exist
  [ ! -d $1 ] && mkdir -p $1

  if [[ -d "$1" ]]; then
    #directiory is valid
    DIR_OUTPUT=$1
  else
    echo "Invalid output directory"
    exit -1
  fi

  #Start ssh-agent
  #This will run a ssh-agent process if there is not one already, and save the output thereof.
  #If there is one running already, we retrieve the cached ssh-agent output and evaluate it which will 
  #set the necessary environment variables. The lifetime of the unlocked keys is set to 1 hour. 
  #See https://wiki.archlinux.org/title/SSH_keys#ssh-agent
  if ! pgrep -u "$USER" ssh-agent > /dev/null; then
      ssh-agent -t 1h > "$XDG_RUNTIME_DIR/ssh-agent.env"
  fi

  if [[ ! "$SSH_AUTH_SOCK" ]]; then
      source "$XDG_RUNTIME_DIR/ssh-agent.env" >/dev/null
  fi

  #Create a control master connection
  ssh -nNf -o ControlMaster=yes -o ControlPath=$SSH_CONTROL_PATH -o ControlPersist=$SSH_CONTROL_PERSIST $SSH_HOST exit

  #Stop seafile 
  #This is not mandatory. However depending on sequence of data and database backup
  #some data may be lost or file system corruption may occur (see seafile admin manual) 
  #stopping the service is the savest option
  stop_user_service "seahub"

  #stop seahub
  stop_user_service "seafile"

  #Dump myql databaes. Make sure backup directory exits
  ssh_cmd "[ ! -d $DIR_DB ]" && ssh_cmd "mkdir -p $DIR_DB"
  mysql_dump

  #===== Transfer backup of seafile and seahub =====================================

  #Transfer database dumps
  echo "Transfer MySQL dumps"
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$DIR_DB $DIR_OUTPUT

  #Transfer seafile config
  echo "Transfer seafile config folder"
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$DIR_SEAFCFG $DIR_OUTPUT

  #Transfer seafile installed folder (contains installation *.tar.gz files)
  echo "Transfer seafile installed folder (contains installation *.tar.gz files)"
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$DIR_SEAFINST $DIR_OUTPUT


  #Transfer seafile avatar folder
  echo "Transfer seafile avatar folder"
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$DIR_SAEFAVA $DIR_OUTPUT

  #===== Transfer systemd unit files ===============================================

  echo "Transfer systemd unit files"
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$SYSTEMD_MNT $DIR_OUTPUT
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$SYSTEMD_USER_SEAFILE $DIR_OUTPUT
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$SYSTEMD_USER_SEAHUB $DIR_OUTPUT

  #===== Transfer nginx config =====================================================

  echo "Transfer nginx config file"
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$NGINX_CONF $DIR_OUTPUT

  #===== Transfer fail2ban config ==================================================

  echo "Transfer systemd unit files"
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$FAIL2BAN_JAIL $DIR_OUTPUT
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$FAIL2BAN_FILAPI $DIR_OUTPUT
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$FAIL2BAN_FILAUTH $DIR_OUTPUT
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$FAIL2BAN_FILURL $DIR_OUTPUT
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$FAIL2BAN_FILWEBDAV $DIR_OUTPUT
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$FAIL2BAN_FILWEBDAVNGINX $DIR_OUTPUT

  #===== Run garbage collection ==================================================

  echo "Run seafile garbadge collector"
  ssh_cmd "$DIR_SEAFLATEST/seaf-gc.sh"

  #===== Transfer seafile data =====================================================

  echo "Transfer seafile data folder"
  rsync $RSYNC_OPT -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$DIR_SEAFDATA $DIR_OUTPUT

  #Verify rsync
  #If the second rsync reports "Number of files transferred: 0" you will know that the files are identical on each side,
  #based on their checksums. 
  echo "Starting verify of data..."
  VERIFY_OUTPUT=$(rsync -aRv --stats --checksum --dry-run -e "ssh -o ControlPath=$SSH_CONTROL_PATH" $SSH_HOST:$DIR_SEAFDATA $DIR_OUTPUT)
  VERIFY_CHK=$(echo "$VERIFY_OUTPUT" | grep -o 'Number of regular files transferred: 0' || true;)

  if [ -n "$VERIFY_CHK" ]; then
    echo -e ""$BLUE"Verify of seafile data directory successful!"$NOCOLOR""
  else
    echo -e ""$RED"Verify of seafile data directory failed!"$NOCOLOR""
    echo -e "rsync --dry-run output:\n"
    echo "$VERIFY_OUTPUT"
    echo -e ""$RED"Script ended with error!"$NOCOLOR""
    exit -1
  fi

  #===== Backup complete ===========================================================

  #Start seafile seahub
  start_user_service seafile
  start_user_service seahub

  #Close the ssh ControlMaster connection manually 
  ssh -o ControlPath=$SSH_CONTROL_PATH -O exit $SSH_HOST 2> /dev/null

  echo -e ""$GREEN"Backup sucessfully finished!"$NOCOLOR""
} | tee `date +"%Y-%m-%d-%H-%M-%S"`.backup.log
