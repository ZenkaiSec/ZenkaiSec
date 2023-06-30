#!/bin/bash
#
#############################################################################
#																			#
# Written by:																#
#																			#
# Gary Zinn																	#
# Network Information Security (NIS) | Cyber Systems						#
# PwC | 4040 West Boy Scout Blvd. | Tampa, FL 33607							#
# Mobile: 813-310-6954 | Office: 813-559-5072								#
# Email: gary.zinn@pwc.com													#
#																			#
#############################################################################
#																			#
# Purpose:																	#
#																			#
# Install Splunk Universal Fowarder (UF) agent on a Linux host and			#
# configure the UF to connect to the proper deployment server.				#
#																			#
#############################################################################
#																			#
# Version: 2018-06-07	(yyyy-mm-dd)										#
#																			#
#############################################################################
#
#
#
##### SET VARIABLES #########################################################
#
# Date/time variable with YYYY-MM-DD_HH.MM.SS format:
_NOW=$(date +%Y-%m-%d_%H.%M.%S)
#
# Name of archive containing Splunk UF installers and TAs:
_InstArchive=Splunk_Linux_UF.tgz
#
#
# Log of this script's output:
# _SplkUFinstLog=SplkUFinstLog_$_NOW.log
_SplkUFinstLog=SplkUFinst_`hostname`_$_NOW.log
#
# Log of this script's error-specific output:
# _SplkUFinstErrLog=SplkUFinstErrLog_$_NOW.log
_SplkUFinstErrLog=SplkUFinstErr_`hostname`_$_NOW.log
#
# Tee output to screen, and append to install log at the same time:
_TEE="tee -a $_SplkUFinstLog"
#
# Tee output to screen, append to install log, and also append to error log:
_TERR="$_TEE $_SplkUFinstErrLog"
#
# Root directory for Splunk installation:
_SplkRootDir=/opt
#
# Splunk home installation directory:
SPLUNK_HOME=$_SplkRootDir/splunkforwarder
#
# Splunkd port:
_splunkdPort=8089
#
# Splunk user name:
_SplkUser=splunker
#
# Splunk user UID:
_SplkUserUID=9980
#
# Splunk user group name:
_SplkGrp=splunker
#
# Splunk user group GID (keep UID and GID same for puppet):
_SplkGrpGID=$_SplkUserUID
#
# Sudo with HOME variable set $_SplkUser:
_sudoSplkUser="sudo -H -u $_SplkUser"
#
# Path to Splunk /bin:
_SplkBin=$SPLUNK_HOME/bin
#
# Path to Splunk /etc
_SplkEtc=$SPLUNK_HOME/etc
#
# Path to Splunk binary:
_splunk=$_SplkBin/splunk
#
# If we find /opt/splunk, we can't install UF!
_SplkSrvHome=$_SplkRootDir/splunk
#
# Switches to silently answer YES to all questions and accept EULA:
# _silent="--answer-yes --no-prompt --accept-license"
_silent="--accept-license --answer-yes --no-prompt"
#
# Splunk init.d path:
_SplkInitd=/etc/init.d/splunk
#
# Splunk init.d comment:
_SplkInitdCmnt="# Splunk hard and soft ulimits, added $_NOW."
#
# Splunk init.d hard ulimit parameter:
_initdUlimH="  ulimit -Hn 65536"
#
# Splunk init.d soft ulimit parameter:
_initdUlimS="  ulimit -Sn 65536"
#
# Splunkd.log:
_SplunkdLog=$SPLUNK_HOME/var/log/splunk/splunkd.log
#
# Splunk edit user:
_editUser="$_splunk edit user"
#
# Splunk add user:
_addUser="$_splunk add user"
#
# TA root path:
_TAroot=$_SplkEtc/apps
#
# Declare an array for TAs to be installed: 
# declare -a _techAddOns
# _techAddOns=(pwc_deploymentclient_ta)
#
# Deployment client TA prefix:
_TApfx="pwc_deployment_ta_"
#
# Command to modify ACL of file in /var/log to add rx to splunker group:
_modVarLogAcls="/usr/bin/setfacl -m g:$_SplkGrp:rx /var/log"
#
# Declare an array of filenames under /var/log to which we will add
# read and execute permissions for splunker group:
declare -a _varLogFiles
_varLogFiles=(cron maillog messages secure spooler yum.log) 
#
# Path to logrotate.d for syslog:
_lrdSyslog=/etc/logrotate.d/syslog
#
# Path to logrotate.d for yum:
_lrdYum=/etc/logrotate.d/yum
#
# Path to auditd.conf:
_auditdConf=/etc/audit/auditd.conf
#
#
##### FUNCTION TO DISPLAY USAGE FOR THIS SCRIPT #############################
#
# Display proper usage syntax, acceptable values, and examples then exit.
# Called if arguments are missing, incorrect, or incomplete:
function display_usage {
	echo ERROR: Required arguments or values are missing or incorrect. |& $_TERR
	echo "You supplied <$_clstr> for PwC Splunk cluster." |& $_TERR
	echo "You supplied <$_UFver> for version of Splunk Universal Forwarder (UF) to install." |& $_TERR
	echo "You supplied <$_silnt> for Silent installation with no screen output." |& $_TERR
	echo |& $_TERR
	echo "Usage: $(basename "$0") -c <cluster> -s <silent> -v <version>" |& $_TERR
	echo "The following arguments with acceptable values are all required:" |& $_TERR
	echo "  -c  PwC Splunk cluster. Use <ahs> for Advisory Hosting Services." |& $_TERR
	echo "      Acceptable values are <ahs>, <cent> for Central cluster, <east>, <west>." |& $_TERR
	echo "  -v  Version of Splunk Universal Forwarder (UF) you wish to install."  |& $_TERR
	echo "      Acceptable values are <7.3.4>, <6.6.6>." |& $_TERR
	echo "  -s  Silent installation with no screen output. Log files are still generated." |& $_TERR
	echo "      Acceptable values are <yes> for silent, <no> for normal screen output."|& $_TERR
	echo |& $_TERR
	echo Example: Install UF v7.3.4, East cluster, screen and log output: |& $_TERR
	echo $(basename "$0") -c east -v 7.3.4 -s no |& $_TERR
	echo Example: Install UF v6.6.6, Central cluster, silently with logs only: |& $_TERR
	echo $(basename "$0") -c cent -v 6.6.6 -s yes |& $_TERR
	exit 1
}
#
#
##### READ ARGUMENTS PASSED TO THIS SCRIPT ##################################
#
while getopts ":c:v:s:" option; do
	case "${option}" in
		c) _clstr=${OPTARG};;
		s) _silnt=${OPTARG};;
		v) _UFver=${OPTARG};;
	esac
done
#
#
##### ASSIGN ARGUMENTS TO VARIABLES #########################################
#
# Assign arguments to variables.  If arguments are missing, invalid, or
# incomplete, jump to usage display function which will display then exit.
#
# -s
case $_silnt in
	yes)	exec 1>/dev/null 2>/dev/null
			echo "You supplied <$_silnt> for Silent installation with no screen output." >> $_SplkUFinstLog
			;;
	no)		echo "You supplied <$_silnt> for Silent installation with no screen output." |& $_TEE
			;;
	*)		display_usage
			;;
esac
#
# -c
case $_clstr in
	ahs|cent|east|west)	echo "You supplied <$_clstr> for PwC Splunk cluster." |& $_TEE
	;;
	*)	display_usage
	;;
esac
#
# -v
case $_UFver in
	7.3.4|6.6.6) echo "You supplied <$_UFver> for Splunk UF version to install." |& $_TEE
	;;
	*) display_usage
	;;
esac	
#
#
#
##### CHECK FOR ROOT ########################################################
#
# Check if this is being run as root and relaunch with sudo if not:
echo |& $_TEE
echo Ensuring script runs as root... |& $_TEE
if [ "$(id -u)" = "0" ]; then
	echo Script is running as root user. |& $_TEE
else
	echo "Relaunching this script as root user." |& $_TEE
	exec sudo "$0" "$@"
fi
echo |& $_TEE
#
#
##### ENSURE THIS IS NOT A SPLUNK SERVER ####################################
#
if [ ! -d $_SplkSrvHome ] ; then
	echo -$_SplkSrvHome- not found, not a Splunk server, OK to continue. |& $_TEE
	echo |& $_TEE
else
	echo "ERROR: FAILED to install Splunk UF. -$_SplkSrvHome- found. Can't install UF on a Splunk server!" |& $_TERR
	exit 1
fi
#
#
##### LOG SHELL VARIABLES ###################################################
#
# Send all shell variables to log file:
echo Sending shell variables to log file... |& $_TEE
if (set -o posix; set) >> $_SplkUFinstLog ; then
	echo Shell variables logged to $_SplkUFinstLog |& $_TEE
else
	echo ERROR: FAILED to log shell variables to $_SplkUFInstLog. |& $_TERR
fi
echo |& $_TEE
#
#
##### EXTRACT TGZ UF AND TA PACKAGE #########################################
#
# Install by extracting installation archive to $_SplkRootDir:
echo Extracting installation archive to $PWD... |& $_TEE
if tar zxvf $_InstArchive >> $_SplkUFinstLog ; then
	echo Extracted installation archive to $PWD. |& $_TEE
else
	echo ERROR: FAILED to extract installation archive to $PWD. |& $_TERR
fi	
echo |& $_TEE
#
#
##### ADD SPLUNKER GROUP ####################################################
#
echo Checking for existing -$_SplkGrp- group... |& $_TEE
if getent group $_SplkGrp > /dev/null ; then
	echo Group -$_SplkGrp- already exists. |& $_TEE
else
	echo |& $_TEE
	echo -$_SplkGrp- not found.  Adding group to Linux... |& $_TEE
	if groupadd -g $_SplkGrpGID $_SplkGrp ; then
		echo -$_SplkGrp- group with GID -$_SplkGrpGID- added to Linux. |& $_TEE
	else
		echo ERROR: FAILED to add -$_SplkGrp- group with GID -$_SplkGrpGID- to Linux. |& $_TERR
	fi
fi	
echo |& $_TEE
#
#
##### ADD SPLUNKER USER AS MEMBER OF SPLUNKER GROUP #########################
#
echo Checking for existing -$_SplkUser- Linux user... |& $_TEE
if getent passwd $_SplkUser > /dev/null; then
	echo Linux user -$_SplkUser- already exists. |& $_TEE
else
	echo |& $_TEE
	echo -$_SplkUser- Linux user not found.  Adding user... |& $_TEE
	if useradd -u $_SplkUserUID -g $_SplkGrpGID $_SplkUser; then
		echo -$_SplkUser- with UID -$_SplkUserUID- added to Linux group -$_SplkGrp- with GID -$_SplkGrpGID-. |& $_TEE
	else
		echo ERROR: FAILED to add -$_SplkUser- with UID -$_SplkUserUID- to Linux group with GID -$_SplkGrpGID-. |& $_TERR
	fi
fi	
echo |& $_TEE
#
#
###### CREATE SPLUNK HOME DIR AND BACK UP ANY EXISTING ######################
#
# Create the SPLUNK_HOME directory:
echo Checking for existing $SPLUNK_HOME directory... |& $_TEE
if [ -d $SPLUNK_HOME ] ; then
	echo Existing $SPLUNK_HOME directory found. |& $_TEE
	echo |& $_TEE
#	Splunk home dir already exists, so back up existing copy:	
	echo Backing up $SPLUNK_HOME to $SPLUNK_HOME"_"$_NOW.tgz... |& $_TEE
	if tar -zcvf $SPLUNK_HOME"_"$_NOW.tgz $SPLUNK_HOME >> $_SplkUFinstLog ; then
		echo Backed up existing $SPLUNK_HOME to $SPLUNK_HOME"_"$_NOW.tgz. |& $_TEE
	else
		echo ERROR: FAILED to back up existing $SPLUNK_HOME to $SPLUNK_HOME"_"$_NOW.tgz. |& $_TERR
	fi
	echo |& $_TEE	
else
#	Splunk home dir doesn't exist, so nothing to back up, create new one:	
	echo Existing $SPLUNK_HOME not directory found, so nothing to back up. |& $_TEE
	echo |& $_TEE
	echo Creating $SPLUNK_HOME directory... |& $_TEE
	if mkdir $SPLUNK_HOME ; then
		echo Created Splunk home directory -$SPLUNK_HOME-. |& $_TEE
	else
		echo ERROR: FAILED to create Splunk home directory -$SPLUNK_HOME-. |& $_TERR
	fi	
echo |& $_TEE
fi
#
#
##### CHECK FOR SPLUNK INSTALLATION PACKAGE #################################
#
# Set variable to name of splunkforwarder .tgz based on version selected:
 _SplkUFinstPkg=`ls splunkforwarder-$_UFver*`
#
# Proceed when installation package is present:
echo Checking for Splunk installation package... |& $_TEE
until [[ -f $_SplkUFinstPkg ]]; do
	echo Splunk installation package NOT FOUND. |& $_TEE
	echo Copy -$_SplkUFinstPkg- to $PWD. |& $_TEE
	read -n 1 -p "Press any key after package is copied..."
	echo |& $_TEE
done
echo Found Splunk installation package |& $_TEE
echo -$_SplkUFinstPkg-, so we can proceed. |& $_TEE
echo |& $_TEE
#
#
##### STOP SPLUNK IF RUNNING ################################################
#
# If we have a current UF installation, stop it from running.
if [ -d $_SplkBin ] ; then
	echo Stopping Splunk... |& $_TEE
	if $_sudoSplkUser $_splunk stop ; then
		echo Successfully stopped Splunk if it was running. |& $_TEE
	else
		echo ERROR: FAILED to stop Splunk. |& $_TERR
	fi
fi	
echo |& $_TEE
#
#
##### INSTALL SPLUNK ENTERPRISE #############################################
#
# Install by extracting installation archive to $_SplkRootDir:
echo Extracting Splunk installation to $_SplkRootDir... |& $_TEE
if tar zxvf $_SplkUFinstPkg -C $_SplkRootDir >> $_SplkUFinstLog ; then
	echo Extracted Splunk installation archive to $_SplkRootDir. |& $_TEE
else
	echo ERROR: FAILED to extract Splunk installation archive to $_SplkRootDir. |& $_TERR
fi	
echo |& $_TEE
#
#
##### ENSURE CORRECT DEPLOYMENT TA IS PRESENT ###############################
#
# Ensure we have the correct deployment TA for the selected cluster
# before proceeding:
echo "UF deployment, so must install deployment TA for $_clstr cluster..." |& $_TEE
until [[ -d $_TApfx$_clstr ]] ; do
	echo Tech add-on package -$_TApfx$_clstr- NOT FOUND. |& $_TEE
	echo |& $_TEE
	echo Copy -$_TApfx$_clstr- "to -$PWD-." |& $_TEE
	read -n 1 -p "Press any key after package is copied..."
	echo |& $_TEE
done
echo Found tech add-on package -$_TApfx$_clstr-, so we can proceed. |& $_TEE
echo |& $_TEE
#
#
##### BACK UP ANY EXISTING TAs ##############################################
#
# Back up any existing tech add-ons (TAs):
if [ -d $_TAroot ] ; then
	echo Backing up any existing TAa in $_TAroot to $_TAroot"_"$_NOW.tgz... |& $_TEE
	if tar -zcvf $_TAroot"_"$_NOW.tgz $_TAroot >> $_SplkUFinstLog ; then
		echo Backed up existing $_TAroot to $_TAroot"_"$_NOW.tgz. |& $_TEE
	else
		echo ERROR: FAILED to back up existing $_TAroot to $_TAroot"_"$_NOW.tgz. |& $_TERR
	fi
echo |& $_TEE
fi
#
#
##### INSTALL CLUSTER-SPECIFIC DEPLOYMENT TA ################################
#
# Install deployment TA for $_clstr cluster:
# for i in "${_techAddOns[@]}"; do
echo "Copying/updating TA from -$PWD- to -$_TAroot-..." |& $_TEE
# if cp -Ru $i $_TAroot/ ; then
if cp -Ru $_TApfx$_clstr $_TAroot/ ; then
#	echo "Copied/updated -$i- to -$_TAroot/-." |& $_TEE
	echo "Copied/updated -$_TApfx$_clstr- to -$_TAroot/-." |& $_TEE
else
#	echo "ERROR: FAILED to copy/update -$i- to -$_TAroot/-." |& $_TERR
	echo "ERROR: FAILED to copy/update -$_TApfx$_clstr- to -$_TAroot/-." |& $_TERR
fi
echo |& $_TEE
# done
#
#
##### CHECK CONNECTIVITY TO DEPLOYMENT SERVER ###############################
#
# Set variable for path to deploymentclient.conf:
_DepCliConf=$_TAroot/$_TApfx$_clstr/local/deploymentclient.conf
#
echo Checking deployment TA -$_DepCliConf- |& $_TEE
echo to determine targetURI address of deployment server... |& $_TEE
#
# Get deployment server IP address from $_DepCliConf:
# Get line starting with targetUri, trim out spaces, cut after
# "=" to get IP and port, then cut before ":" to get just IP addr:
_DepSrvIP=$( grep ^targetUri $_DepCliConf | tr -d ' ' | cut -d'=' -f2 | cut -d':' -f1 )
#
echo Determined targetURI server address is $_DepSrvIP. |& $_TEE	
echo |& $_TEE
#	
echo Checking connectivity to $_clstr deployment server... |& $_TEE
if (echo > /dev/tcp/$_DepSrvIP/$_splunkdPort) >/dev/null 2>&1 ; then
	echo Can reach $_clstr cluster deployment server at $_DepSrvIP on TCP port $_splunkdPort. |& $_TEE
else
	echo ERROR: FAILED to reach $_clstr deployment server at $_DepSrvIP on TCP $_splunkdPort. |& $_TERR
fi
echo |& $_TEE
#	
#
##### CHANGE OWNERSHIP OF SPLUNK_HOME #######################################
#
echo Changing ownership of $SPLUNK_HOME to $_SplkUser user and $_SplkGrp group: |& $_TEE
if chown -R $_SplkUser:$_SplkGrp $SPLUNK_HOME; then
	echo Changed ownership of $SPLUNK_HOME to $_SplkUser user and $_SplkGrp group. |& $_TEE
else
	echo ERROR: FAILED to change ownership of $SPLUNK_HOME to $_SplkUser user and $_SplkGrp group. |& $_TERR
fi
echo |& $_TEE	
#
#
##### START SPLUNK AS NON-ROOT $_SplkUser ###################################
#
echo Starting Splunk as -$_SplkUser-, setting home var, and accepting license... |& $_TEE
if $_sudoSplkUser $_splunk start $_silent |& $_TEE ; then
	echo Started Splunk as -$_SplkUser-, set home var, and accepted license. |& $_TEE
else
	echo ERROR: FAILED to start Splunk as -$_SplkUser-, set home var, and accept license. |& $_TERR
fi
echo |& $_TEE
#
#
##### ENABLE BOOT START #####################################################
#
# THIS SECTION MUST COME BEFORE MODIFYING SPLUNK INIT.D SECTION
#
echo Enabling boot start for user -$_SplkUser-... |& $_TEE
if $_splunk enable boot-start -user $_SplkUser ; then
	echo Enabled boot-start for user -$_SplkUser-. |& $_TEE
else
	echo ERROR: FAILED to enable boot-start for user -$_SplkUser-. |& $_TERR
fi
echo |& $_TEE	
#
#
##### MODIFY SPLUNK INIT.D ##################################################
#
# THIS SECTION MUST COME AFTER ENABLE BOOT START SECTION
#
echo Adding hard and soft ulimits to -$_SplkInitd-... |& $_TEE
# Insert correct lines before the "  echo Starting Splunk..." line to set
# hard and soft ulimits required by Splunk in $_SplkInitd:
if sed -i "/^  echo Starting Splunk.../i\\$_SplkInitdCmnt\n$_initdUlimH\n$_initdUlimS\n" $_SplkInitd ; then
	echo Added hard and soft limits to -$_SplkInitd-. |& $_TEE
else
	echo ERROR: FAILED to add hard and soft limits to -$_SplkInitd-. |& $_TERR
fi
echo |& $_TEE
#
#
##### MODIFY /VAR/LOG FILE ACLS #############################################
#
# Make Sorin Ban's file ACL additions so $_SplkGrp has read and execute access
# for certain log files in /var/log, so system logs can be collected while
# running Splunk as non-root $_SplkUser, which belongs to $_SplkGrp.
echo Modifying ACL for log files in /var/log, adding rx to $_SplkGrp... |& $_TEE
for i in "${_varLogFiles[@]}"; do
	if $_modVarLogAcls/$i ; then
		echo Modified /var/log/$i ACL, adding rx rights for $_SplkGrp. |& $_TEE
	else
		echo ERROR: FAILED to modify /var/log/$i ACL, rx rights for $_SplkGrp not added. |& $_TERR
	fi	
done
echo |& $_TEE
#
#
##### CHANGE VAR/LOG/AUDIT GROUP TO $_SplkGrp ###############################
#
# Recursively change group of /var/log/audit to $_SplkGrp, includes audit.log:
echo Recursively changing group of /var/log/audit to -$_SplkGrp-... |& $_TEE
if chgrp -R $_SplkGrp /var/log/audit |& $_TEE ; then
	echo Changed group of /var/log/audit to -$_SplkGrp-. |& $_TEE
else
	echo ERROR: FAILED to change group of /var/log/audit to -$_SplkGrp-. |& $_TERR
fi
echo |& $_TEE	
#
#
##### ADD /var/log file ACLS TO /etc/logrotate.d/syslog FOR $_SplkGrp #######
#
# Note: If error b/c /var/log/yum.log is also being set in postrotate, make
# another array w/o it for this section. Should be ok as missingok is set.
#
# Add ACL mods to logrotate.d/syslog in postrotate section so
# $_SplkGrp retains rx after log rotation:
echo Adding ACL mods to $_lrdSyslog... |& $_TEE
# Add ACL mods to /etc/logrotate.d/syslog before line with "endscript":
for i in "${_varLogFiles[@]}"; do
	if sed -i "/^    endscript/i\        $_modVarLogAcls/$i" $_lrdSyslog ; then
		echo Added "$_modVarLogAcls/$i" to $_lrdSyslog |& $_TEE
	else
		echo ERROR: FAILED to add "$_modVarLogAcls/$i" to $_lrdSyslog. |& $_TERR
	fi
done	
echo |& $_TEE
#
#
##### ADD /var/log file ACLS TO /var/log/yum.log FOR $_SplkGrp ##############
#
# Add postrotate section and ACL mods to /var/log/yum.log so $_SplkGrp
# retains read and execute (rx) after log rotation:
echo Adding postrotate, ACL mods, and endscript to $_lrdYum... |& $_TEE
# Add ACL mods to /var/log/yum.log before line with "}":
if sed -i "/^\}/i\    postrotate\n    $_modVarLogAcls\/yum.log\n    endscript" $_lrdYum ; then
	echo Added "$_modVarLogAcls/yum.log" to $_lrdYum |& $_TEE
else
	echo ERROR: FAILED to add "$_modVarLogAcls/yum.log" to $_lrdYum. |& $_TERR
fi
echo |& $_TEE
#
#
##### CHANGE auditd.conf LOG GROUP TO SPLUNKER ##############################
#
# Rem out log_group = (default is root)
echo Commenting out existing $_auditdConf log_group setting... |& $_TEE
if sed -i /^"log_group*"/s/^/"# "/ $_auditdConf ; then
	echo Commented out existing $_auditdConf log_group setting. |& $_TEE
else
	echo ERROR: FAILED to comment out existing $_auditdConf log_group setting. |& $_TERR
fi
echo |& $_TEE
#
# Find line above line starting with # log_group and add log_group=$_SplkUser
echo Changing $_auditdConf log group to $_SplkUser... |& $_TEE
if sed -i "/^# log_group*/i\log_group = \\$_SplkUser" $_auditdConf ; then
	echo Added $_auditdConf log_group = $_SplkUser setting. |& $_TEE
else
	echo ERROR: FAILED to add $_auditdConf log_group = $_SplkUser setting. |& $_TERR
fi
echo |& $_TEE
#
#
##### RESTART SPLUNK ########################################################
#
echo Restarting Splunk... |& $_TEE
if $_sudoSplkUser $_splunk restart $_silent |& $_TEE ; then
	echo Successfully restarted Splunk. |& $_TEE
else
	echo ERROR: FAILED to restart Splunk. |& $_TERR
fi
echo |& $_TEE
#
#
##### REPORT ON CREATED LOG FILES  ##########################################
#
# Check for presence of log file and alert user if present:
if ! [[ -f $_SplkUFInstErrLog ]] ; then
	echo No error log was created. |& $_TEE
	echo See installation log $_SplkUFinstLog for full installation details. |& $_TEE
else
	echo ERROR: FAILED to install with no errors - error log generated. |& $_TEE
	echo See error log $_SplkUFInstErrLog for error details. |& $_TEE
	echo |& $_TEE
	echo See $_SplkUFinstLog for full installation details. |& $_TERR
fi
echo |& $_TEE
#
#
##### END OF SCRIPT #########################################################
#
echo End of $(basename "$0") script. |& $_TEE
#
#
#############################################################################
#############################################################################
exit
