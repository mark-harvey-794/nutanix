#!/usr/bin/bash
# vim: ts=4

# Disclaimer: Usage of this tool must be used only on nutanix diamond platform
# You can review source code from https://github.com/nogodan1234/nutanix/blob/master/taeho_rca.sh
# Downloadable from diamond : curl -OL https://raw.githubusercontent.com/nogodan1234/nutanix/master/taeho_rca.sh
# Version of the script: Version 1
# Compatible software version(s): ALL AOS version - ncc/logbay logset
# Brief syntax usage: diamond$sh taeho_rca.sh

# Check if a directory 'esx' exists
function is_esx()
{
	find ~/shared/${CASE_NUM}/ -type d -name esx -print | wc -l
}

# Display any different version numbers and log entry if found
# Not perfect as it will display the first entry found, followed by any changes:
# One example..
#NTNX-Log-2020-04-22-1350706189197693814-1587550616-PE-10.117.79.120/cvm_logs/log_collector.out.20200422-142540:I0422 14:25:55.686937 8175 cvmconfig.go:297] Ncc Version number 3.7.1.2
#NTNX-Log-2020-04-22-1350706189197693814-1587550616-PE-10.117.79.120/cvm_logs/log_collector.out.20190618-225829:I0618 22:58:29.834937 14707 cvmconfig.go:230] Ncc Version number 3.6.2
#NTNX-Log-2020-04-22-1350706189197693814-1587550616-PE-10.117.79.120/cvm_logs/log_collector.out.20190618-225829:I0629 09:42:55.052053 12512 cvmconfig.go:297] Ncc Version number 3.7.1.2

function ncc_version_number()
{
	VER=" "

	# runtime not using 'bash' - use tmp file
	# done < <(rg -z "Ncc Version number" -g "log_collector.out*" | grep -v "stopped searching binary file") - doesn't work if "sh ./taeho_rca.sh"
	rg -z "Ncc Version number" -g "log_collector.out*" | grep -v "stopped searching binary file" > /tmp/ncc_vers.$$
	while IFS= read -r line
	do
		A=`echo $line | sed -e 's/.*Ncc Version number //g'`
		if [ "$A" != "$VER" ]; then
			echo $line
			VER=$A
		fi
	done < /tmp/ncc_vers.$$

	rm -f /tmp/ncc_vers.$$
}

# unique_FRU: Reduce number of duplicate entries of:
# ------
# FRU Device Description : Builtin FRU Device (ID 0)
# Chassis Type          : Other
# Chassis Part Number   : CSE-819UTS-R1K02P-T
# Chassis Serial        : C819UAG51CC0045
# Board Mfg Date        : Mon Jan  1 00:00:00 1996
# Board Mfg             : Supermicro
# Board Product         : NONE
# Board Serial          : OM17BS001736
# Board Part Number     : X10DRU-I+-G5-NI22
# Product Manufacturer  : Nutanix
# Product Name          : NONE
# Product Part Number   : NX-3175-G5
# Product Version       : NONE
# Product Serial        : 18FM76030112
# Product Asset Tag     : 8374351283058692927
# ------
# but if the Product Serial changes, print the 'new' record

function unique_FRU()
{
	VER=""
	STARTBLOCK=""
	OK2PRINT=""

	rg -z "FRU Device Description" -A14 -g "hardware_info*" > /tmp/unique_fru.$$

	while IFS= read -r line
	do

		# start with 'FRU Device Description'
		if [[ $line == *"FRU Device Description"* ]] && [ -z $STARTBLOCK ]; then
			STARTBLOCK="Y"
		fi

		# We're OK to spit out the line
		if [ ! -z $OK2PRINT ] && [ ! -z $STARTBLOCK ]; then
			echo "$line"
		fi

		# Find serial number first, set OK to print
		if [[ $line == *"Product Serial"* ]] && [ ! -z $STARTBLOCK ]; then
			A=`echo $line | sed -e 's/.*Product Serial //g'`
			# if a different serial number, reset the 'start block' flag
			if [ "$A" != "$VER" ]; then
				VER=$A
				STARTBLOCK=""
				OK2PRINT="Y"
			fi
		fi
		# If 'start block' is set, and we encounter last line in block
		# clear the OK2PRINT flag
		if [ ! -z "$VER" ] && [ ! -z ${STARTBLOCK} ]; then
			if [[ $line == *"Product Asset Tag"* ]]; then   # Found end of block
				OK2PRINT=""
			fi
		fi

	done < /tmp/unique_fru.$$

	rm -f /tmp/unique_fru.$$
}

# ######### main(): execution starts here #########

echo "#############################################"
echo " What is the case number you want to analize? "
echo " Log will be extracted on ~/shared/$CASE_NUM "
echo "#############################################"
read CASE_NUM

echo "#############################################"
echo " Removing existing directory for the case if exists "
echo " rm -rf ~/shared/$CASE_NUM "
echo " rm -rf ~/tmp/$CASE_NUM"
echo "#############################################"
rm -rf ~/shared/$CASE_NUM
rm -rf ~/tmp/$CASE_NUM
mkdir ~/tmp/$CASE_NUM

echo "#############################################"
echo " Extracting log bundle from ncc/logbay "
echo "#############################################"
carbon extract $CASE_NUM
#carbon logbay $CASE_NUM
cd ~/shared/$CASE_NUM
#cd `ls -l | grep '^d' | grep -v meta | awk '{print $9}'`

ESX=`is_esx`

echo "#############################################"
echo " Network Status Check "
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
find . -name ping_hosts.INFO* -exec cat {} \; | egrep -v "IP : time" | awk '/^#TIMESTAMP/ || $3>13.00 || $3=unreachable' | egrep -B1 " ms|unreachable" | egrep -v "\-\-" > ~/tmp/$CASE_NUM/ping_hosts.txt
#find . -name ping_gateway.INFO* -exec cat {} \; | egrep -v "IP : time" | awk '/^#TIMESTAMP/ || $3>13.00 || $3=unreachable' | egrep -B1 " ms|unreachable" | egrep -v "\-\-" > ~/tmp/$CASE_NUM/ping_gw.txt
rg -z "unreachable" -B2 -g "ping_gateway*"  > ~/tmp/$CASE_NUM/ping_gw.txt
find . -name ping_cvm_hosts.INFO* -exec cat {} \; | egrep -v "IP : time" | awk '/^#TIMESTAMP/ || $3>13.00 || $3=unreachable' | egrep -B1 " ms|unreachable" | egrep -v "\-\-" > ~/tmp/$CASE_NUM/ping_cvm.txt
sleep 2

echo "#############################################"
echo " AOS Version check"
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
 rg -z "release" -g release_version																| tee -a ~/tmp/$CASE_NUM/AOS_ver.txt
sleep 2

echo "#############################################"
echo " Hypervisor Version check"
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
 rg -z "release" -g sysctl_info.txt																| tee -a  ~/tmp/$CASE_NUM/hyper_ver.txt
 rg -z "esx_version:" -A3 -g esx_info															| tee -a  ~/tmp/$CASE_NUM/hyper_ver.txt
 rg -z "hypervisor_full_name" -g node															| tee -a  ~/tmp/$CASE_NUM/hyper_ver.txt
sleep 2

echo "#############################################"
echo " Network Segmentation Check"
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
 rg -z "enable" -g microseg_status_*															| tee -a  ~/tmp/$CASE_NUM/net_seg.txt
sleep 2

echo "#############################################"
echo " Log collector run time"
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
rg -z "Log Collector Start time" -g sysctl_info.txt												| tee -a  ~/tmp/$CASE_NUM/ncc_run_time.txt
rg -z "Log Collector Start time" -g ncc_info.txt												| tee -a  ~/tmp/$CASE_NUM/ncc_run_time.txt
rg -z "Log Collector Start time" -g "hardware_info.INFO*" | tail -1								| tee -a  ~/tmp/$CASE_NUM/ncc_run_time.txt
sleep 2

echo "#############################################"
echo " Cluster ID/Timezone"
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
rg -z -B1 "cluster_name" -g "zeus_config.txt"   | sort -u										| tee -a  ~/tmp/$CASE_NUM/cluster_id_timezone.txt
rg -z "timezone" -g "zeus_config.txt"	        | sort -u										| tee -a  ~/tmp/$CASE_NUM/cluster_id_timezone.txt
sleep 2

echo "#############################################"
echo " Foundation verion"
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
rg "4|3|2"  -g foundation_version																| tee -a  ~/tmp/$CASE_NUM/foundation_ver.txt
sleep 2

echo "#############################################"
echo " Pheonix verion"
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
rg "4|3|2"  -g phoenix_version																	| tee -a  ~/tmp/$CASE_NUM/phoenix_ver.txt
sleep 2

echo "#############################################"
echo " Upgrade history"
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
rg -z release -g "upgrade.history"																| tee -a  ~/tmp/$CASE_NUM/upgrade_history.txt
sleep 2

echo "#############################################"
echo " Hardware Model Check"
echo " Output file will be generated in ~/tmp/$CASE_NUM/HW.txt"
echo "#############################################"
unique_FRU																						| tee -a ~/tmp/$CASE_NUM/HW.txt
sleep 2

echo "#############################################"
echo " BMC/BIOS version"
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
 rg -z "bmc info" -A5 -g "hardware_info*"														| tee -a  ~/tmp/$CASE_NUM/bmc_ver.txt
if [ "X${ESX}" == "X0" ]; then
 rg -z "BIOS Information" -A2 -g "hardware_info*" | sort -u 									| tee -a  ~/tmp/$CASE_NUM/bios_ver.txt
else
 # ESX hardware_info...
 rg -z "BIOS Info" -A3 -g "hardware_info*" | egrep "Version|Release" | sort -u					| tee -a  ~/tmp/$CASE_NUM/bios_ver.txt
fi
sleep 2

echo "#############################################"
echo " Hypervisor network error check "
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
rg -z "Network unreachable"																		| tee -a ~/tmp/$CASE_NUM/esxi.network.err.txt
rg -z "NIC Link is Down" -g "vmkernel.*"														| tee -a ~/tmp/$CASE_NUM/hyper_network.err.txt
rg -z "NIC Link is Down" -g "message*"															| tee -a  ~/tmp/$CASE_NUM/hyper_network.err.txt
rg -z "NIC Link is Down" -g "dmesg*"															| tee -a ~/tmp/$CASE_NUM/hyper_network.err.txt
sleep 2

echo "#############################################"
echo "CVM/hypervisor reboot check "
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
sleep 2
rg -z "system boot" -g "config.txt"																| tee -a  ~/tmp/$CASE_NUM/cvm_reboot.txt
rg -z "system boot" -g "last_reboot.txt"														| tee -a  ~/tmp/$CASE_NUM/cvm_reboot.txt
rg -z "system boot" -g "kvm_info.txt"															| tee -a ~/tmp/$CASE_NUM/ahv_reboot.txt

echo "#############################################"
echo " NCC version check "
echo " Output file will be generated in ~/tmp/$CASE_NUM folder"
echo "#############################################"
ncc_version_number																				| tee -a ~/tmp/$CASE_NUM/NCC_Ver.txt
sleep 2

echo "#############################################"											| tee -a ~/tmp/$CASE_NUM/Disk_failure.txt
echo " Smartctl/Disk failure check"																| tee -a ~/tmp/$CASE_NUM/Disk_failure.txt
echo "#############################################"											| tee -a ~/tmp/$CASE_NUM/Disk_failure.txt
rg "attempting task abort! scmd"																| tee -a ~/tmp/$CASE_NUM/Disk_failure.txt
rg -z "SATA DOM|sudo smartctl | overall-health" -g "hardware_info"								| tee -a ~/tmp/$CASE_NUM/Disk_failure.txt
sleep 2

echo "#############################################"											| tee -a ~/tmp/$CASE_NUM/Cass_Too_many_SStables-ENG-177414.txt
echo "1. ENG-177414 - Cassandra Too many SSTables "												| tee -a ~/tmp/$CASE_NUM/Cass_Too_many_SStables-ENG-177414.txt
echo "#############################################"											| tee -a ~/tmp/$CASE_NUM/Cass_Too_many_SStables-ENG-177414.txt
sleep 2
rg -z -B 1 -A 1 "Too many SSTables found for Keyspace : medusa" -g "cassandra*"					| tee -a ~/tmp/$CASE_NUM/Cass_Too_many_SStables-ENG-177414.txt
sleep 2

echo "#############################################"											| tee -a ~/tmp/$CASE_NUM/FA67metadata_corrupt.txt
echo "FA67 Metadata corruption due to skipped row"												| tee -a ~/tmp/$CASE_NUM/FA67metadata_corrupt.txt
echo "#############################################"											| tee -a ~/tmp/$CASE_NUM/FA67metadata_corrupt.txt
rg -z -B 1 -A 1 "Skipping row DecoratedKey"														| tee -a ~/tmp/$CASE_NUM/FA67metadata_corrupt.txt

echo "#############################################"											| tee -a ~/tmp/$CASE_NUM/node_degraded.txt
echo "ONCALL-8062 fix in 5.10.9 Wrong CVM became degraded "										| tee -a ~/tmp/$CASE_NUM/node_degraded.txt
echo "#############################################"											| tee -a ~/tmp/$CASE_NUM/node_degraded.txt
rg -z "notification=NodeDegraded service_vm_id="												| tee -a ~/tmp/$CASE_NUM/node_degraded.txt

#rg -z -B 1 -A 1 "Stargate on node"| rg "is down" .
echo "#############################################"											| tee -a ~/tmp/$CASE_NUM/OOM.txt
echo "2. ISB-101-2019: Increasing the CVM Common Memory Pool "									| tee -a ~/tmp/$CASE_NUM/OOM.txt
echo "#############################################"											| tee -a ~/tmp/$CASE_NUM/OOM.txt
sleep 2
rg -z -B 1 -A 1 "Out of memory: Kill process"| egrep -i "ServiceVM_Centos.0.out|NTNX.serial.out.0"  | tee -a ~/tmp/$CASE_NUM/OOM.txt

echo "#############################################"											| tee -a ~/tmp/$CASE_NUM/Cass_Corrupt_table.txt
echo "3. ENG-218803 , ISB-096-2019 Corrupt sstables"											| tee -a ~/tmp/$CASE_NUM/Cass_Corrupt_table.txt
echo "#############################################"											| tee -a ~/tmp/$CASE_NUM/Cass_Corrupt_table.txt
sleep 2
rg -z -B 1 -A 1 "Corrupt sstables" -g "cassandra*"												| tee -a ~/tmp/$CASE_NUM/Cass_Corrupt_table.txt
rg -z -B 1 -A 1 "kCorruptSSTable" -g "cassandra*"												| tee -a ~/tmp/$CASE_NUM/Cass_Corrupt_table.txt
rg -z -B 1 -A 1 "java.lang.AssertionError" -g "cassandra*"										| tee -a ~/tmp/$CASE_NUM/Cass_Corrupt_table.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "4. Stargate health check"																	| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
sleep 2
rg -z "Corruption fixer op finished with errorkDataCorrupt on egroup" -g "stargate.*"			| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
#ISB-072-2018
rg -z "kUnexpectedIntentSequence" -g "stargate.*"												| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "Check Backend error, please check cassandra status"										| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "ParseReturnCodes: Backend returns error 'Timeout Error' for extent group id:" -g "stargate.*" | tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "Inserted HA route on host" -g "genesis*"													| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "Stargate exited" -g "stargate*"															| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "QFATAL Timed out waiting for Zookeeper session establishment" -g "stargate*"				| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "Becoming NFS namespace master"															| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "Hosting of virtual IP "																	| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
#rg -z "nfs_remove_op.cc"
rg -z "Created iSCSI session for leading connection"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "SMB-SESSION-SETUP request got for connection"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
#echo "ENG-30397 ext4 file corruption"
#rg -z "kSliceChecksumMismatch"
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "Checking ... Disk IO latency check > 100ms"												| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "AIO disk" -g "stargate*"  | sort -k 11n | tail -30										| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "Starting Stargate"																		| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "Becoming NFS namespace master"															| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
#rg -z "Requested deletion of egroup"
rg -z "completed with error kRetry for vdisk"													| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "Checking ... SSD tier running out of space"												| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "Unable to pick a suitable replica" -g "stargate*"										| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "Checking ... Unfixable egroup corruption"													| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "are either unavailable or corrupt"														| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "NFS server requested client to retry"														| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "Checking ... NFS3ERR_JUKEBOX error"														| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "Checking ... Oplog corrupt detection"														| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "is missing on all the replicas"															| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "Checking ... RSS memory dump/crash"														| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "Exceeded resident memory limit: Aborting"												| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "Run out of storage space"																	| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "failed with error kDiskSpaceUnavailable" -g "stargate.INFO*"								| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "Checking ... Stargate FATAL"																| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg '^F[0-9]{4}' -g 'stargate*'																	| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "Checking peer service dead"																| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt
rg -z "has been found dead" | grep -v "stopped searching binary file"							| tee  -a ~/tmp/$CASE_NUM/Stargate_health.txt

echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/revoke_token.txt
echo "5. Token revoke failure"																	| tee   -a ~/tmp/$CASE_NUM/revoke_token.txt
echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/revoke_token.txt
sleep 2
rg -z "Failed to revoke token from"																| tee   -a ~/tmp/$CASE_NUM/revoke_token.txt

echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/scsi_controller.txt
echo "6. scsi controller timeout"																| tee   -a ~/tmp/$CASE_NUM/scsi_controller.txt
echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/scsi_controller.txt
sleep 2
rg -z "mpt3sas_cm0: Command Timeout"															| tee   -a ~/tmp/$CASE_NUM/scsi_controller.txt

echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "7. Cassandra Check"																		| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
sleep 2
rg -z "Could not start repair on the node"														| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z "as degraded after analyzing"																| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt

echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "Cass SSD disk write latency high, please check SSD status"								| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z "local write hasn't succeeded yet" -g "system.log.INFO.*"									| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt

echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "# ENG-149005,ENG-230635 Heap Memory issue #"												| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z "Paxos Leader Writer timeout waiting for replica leader" -g "system.log*" | grep -v vdiskblockmap		| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "# 2 node cluster Cassandra issue ISB-102-2019 #"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
#https://confluence.eng.nutanix.com:8443/display/STK/ISB-102-2019%3A+Data+inconsistency+on+2-node+clusters
rg -z "has been found dead"	-g "cassandra_monitor*"												| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z "does not exist when extent oid="															| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z "Leadership acquired for token:" -g "cassandra_monitor*"									| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z "RegisterForLeadership for token:" -g "cassandra_monitor*"								| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z "with transformation type kCompressionLZ4 and transformed length"							| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
#rg -z "Failing GetEgroupStateOp as the extent group does not exist on disk"
echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "Cassandra heap memory congestion check"													| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
#rg -z "GCInspector.java" -g "system.log*"														| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z "over the critical alarm level" -g "system.log*"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "# Cassandra restart/crash"																| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "#############################################"											| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z "Logging initialized" -g "system.log*"													| tee   -a ~/tmp/$CASE_NUM/cassandra_check.txt

echo "###########################" 																| tee -a ~/tmp/$CASE_NUM/metadata_detach.txt
echo "metadata node detach task start/end"   													| tee -a ~/tmp/$CASE_NUM/metadata_detach.txt
echo "###########################" 																| tee -a ~/tmp/$CASE_NUM/metadata_detach.txt
rg -z  "Marking"  -g "dynamic_ring_changer.INFO*"  												| tee -a ~/tmp/$CASE_NUM/metadata_detach.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Hades_disksvc_error.txt
echo "8. Hades Disk service check"																| tee  -a ~/tmp/$CASE_NUM/Hades_disksvc_error.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Hades_disksvc_error.txt
sleep 2
rg -z "Failed to start DiskService. Fix the problem and start again" -g "genesis*"				| tee  -a ~/tmp/$CASE_NUM/Hades_disksvc_error.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/curator_scan_failure.txt
echo "9. Curator Scan Failure due to network issue"												| tee  -a ~/tmp/$CASE_NUM/curator_scan_failure.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/curator_scan_failure.txt
sleep 2
rg -z "Http request timed out" -g "curator.*"													| tee  -a ~/tmp/$CASE_NUM/curator_scan_failure.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/curator_scan_failure.txt
echo "Curator Scan Failure due to zk version mismatch - KB7058"									| tee  -a ~/tmp/$CASE_NUM/curator_scan_failure.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/curator_scan_failure.txt
sleep 2
rg -z "Write node finished with error kBadVersion for Zeus" -g "curator.*"						| tee  -a ~/tmp/$CASE_NUM/curator_scan_failure.txt


echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "10. Acropolis service crash"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
sleep 2
rg -z "Acquired master leadership" -g "acropolis.*"												| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
rg -z "Failed to re-register with Pithos after 60 seconds"										| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
rg -z "Time to fire reconcilliation callback took" -g "acropolis.out*"							| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "VM Delete log"																			| tee  ~/tmp/$CASE_NUM/VM_delete.txt
sleep 2
rg -z "notification=VmDeleteAudit"	-g "acropolis.out*"											| tee  -a ~/tmp/$CASE_NUM/VM_delete.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/pithos_svc_crash.txt
echo "11. Pithos service crash - ENG-137628"													| tee  -a ~/tmp/$CASE_NUM/pithos_svc_crash.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/pithos_svc_crash.txt
sleep 2
rg -z "GetRangeSlices RPC failed (kTimeout: TimedOutException())"								| tee  -a ~/tmp/$CASE_NUM/pithos_svc_crash.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/file_desc.txt
echo "12. File Descriptior Check - KB 3857 ENG-119268"											| tee  -a ~/tmp/$CASE_NUM/file_desc.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/file_desc.txt
sleep 2
rg -z "Resource temporarily unavailable"														| tee  -a ~/tmp/$CASE_NUM/file_desc.txt
rg -z "[ssh] <defunct>"| wc -l																	| tee  -a ~/tmp/$CASE_NUM/file_desc.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/frodo_svc_crash.txt
echo "13. Stargate crashing due to AHV frodo service failure ONCALL-7326"						| tee  -a ~/tmp/$CASE_NUM/frodo_svc_crash.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/frodo_svc_crash.txt
sleep 2
rg -z "Check failed: count_ == write_iobuf_->size()"											| tee  -a ~/tmp/$CASE_NUM/frodo_svc_crash.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/pithos_vdisk_update_failure.txt
echo "14. Pithos vdisk update failure  ONCALL-7326 ENG-238450"									| tee  -a ~/tmp/$CASE_NUM/pithos_vdisk_update_failure.txt
echo "maybe good to check with pithos_cli -exhaustive_validate"									| tee  -a ~/tmp/$CASE_NUM/pithos_vdisk_update_failure.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/pithos_vdisk_update_failure.txt
sleep 2
rg -z "Failed to modify and update all the given vdisks, only 0 were successfully updated"		| tee  -a ~/tmp/$CASE_NUM/pithos_vdisk_update_failure.txt
rg -z "Not performing selective vdisk severing as no vdisks are selected for copy blockmap"		| tee  -a ~/tmp/$CASE_NUM/pithos_vdisk_update_failure.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/missing_egroup_replica.txt
echo "15. Missing egroup replica check ONCALL-4514"												| tee  -a ~/tmp/$CASE_NUM/missing_egroup_replica.txt
echo  "need to confirm with medusa_printer and egroup_collector.py "							| tee  -a ~/tmp/$CASE_NUM/missing_egroup_replica.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/missing_egroup_replica.txt
sleep 2
rg -z "changed from 1 to 0 due to egroup" -g "curator.*"										| tee  -a ~/tmp/$CASE_NUM/missing_egroup_replica.txt
# Run egroup_collector.py from diamond server
#echo "/users/eng/tools/egroup_corruption/egroup_collector.py --egroup_id $EID --output dir /users/taeho.choi/tmp" | tee  -a ~/tmp/$CASE_NUM/missing_egroup_replica.txt
#echo "medusa_printer --lookup=egid --egroup_id=$EID"											| tee  -a ~/tmp/$CASE_NUM/missing_egroup_replica.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/physical_disk_op.txt
echo "16. Check disk operation from hades log"													| tee  -a ~/tmp/$CASE_NUM/physical_disk_op.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/physical_disk_op.txt
sleep 2
rg -z "Handling hot-remove event for disk" -g "hades.out*"										| tee  -a ~/tmp/$CASE_NUM/physical_disk_op.txt
rg -z "Handling hot-plug" -g "hades.out*"														| tee  -a ~/tmp/$CASE_NUM/physical_disk_op.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/physical_disk_op.txt
echo "17. Disk forcefully was pulled off "														| tee  -a ~/tmp/$CASE_NUM/physical_disk_op.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/physical_disk_op.txt
sleep 2
rg -z "is not marked for removal and has been forcefully pulled"								| tee  -a ~/tmp/$CASE_NUM/physical_disk_op.txt
#disk_operator accept_old_disk $DISK_SN

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/iscsi_reset.txt
echo "18. iscsi connection reset "																| tee  -a ~/tmp/$CASE_NUM/iscsi_reset.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/iscsi_reset.txt
sleep 2
rg -z "Removing initiator iqn" -g "stargate*"													| tee  -a ~/tmp/$CASE_NUM/iscsi_reset.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/HBA_reset.txt
echo "19. HBA reset reset "																		| tee  -a ~/tmp/$CASE_NUM/HBA_reset.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/HBA_reset.txt
sleep 2
rg -z "mpt3sas_cm0: sending diag reset"	-g "messages*"										    | tee  -a ~/tmp/$CASE_NUM/HBA_reset.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Cerebro_bug-ENG24713.txt
echo "20. Cerebro bug ENG-247313 "																| tee  -a ~/tmp/$CASE_NUM/Cerebro_bug-ENG24713.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Cerebro_bug-ENG24713.txt
sleep 2
rg -z "Cannot reincarnate a previously detached entity without an incarnation_id"				| tee  -a ~/tmp/$CASE_NUM/Cerebro_bug-ENG24713.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Ergon_task_issue.txt
echo "21. ergon task issue ENG-247313 "															| tee  -a ~/tmp/$CASE_NUM/Ergon_task_issue.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/Ergon_task_issue.txt
sleep 2
rg -z "Cache sync with DB failed" -g "ergon.*"													| tee  -a ~/tmp/$CASE_NUM/Ergon_task_issue.txt
rg -z "Cache sync with DB failed" -g "minerva_ha_dispatcher.*"									| tee  -a ~/tmp/$CASE_NUM/Ergon_task_issue.txt

echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/seg_fault.txt
echo "22. Segmentation Fault Check possiblely ovsd crash(ENG-279410)"							| tee  -a ~/tmp/$CASE_NUM/seg_fault.txt
echo "#############################################"											| tee  -a ~/tmp/$CASE_NUM/seg_fault.txt
sleep 2
rg -z "Segmentation fault" -B1 -A1																| tee  -a ~/tmp/$CASE_NUM/seg_fault.txt

#Adding more entry on 20 March 2020

echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "Acropolis service check"																	| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt

echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "Displays AHV master changes"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
rg -z "Acquired master leadership"  -g "acropolis.out*"											| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt

echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "Displays Acropolis crash events."															| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
rg -z  "Could not find parcels for VM" -g "acroplos.out*"										| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt

echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "Displays Acropolis crash events."															| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
rg -z  "ValueError: bytes is not a 16-char string" -g "acroplos.out*"							| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt

echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "Detecting multiple VM creation with same NIC UUID."										| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
rg -z  "failed with error: virtual_nic with uuid" -g "acroplos.out*"							| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt

echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "Acropolis crashes when there are VMs in the cluster with affinity and anti-affinity configured and enabling HA, to HA-RS(ENG-109729)"	| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
rg -z  "AcropolisNotFoundError: Unknown VmGroup:" -g "acroplos.out*"							| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt

echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "Displays Acropolis crash due to abort migration events - ENG-232484, KB 7925, MTU check"	| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
rg -z  "Unable to find matching parcel for VM" -g "acroplos.out*"								| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt

echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "Displays Acropolis crash due to master initialization taking too long - ENG-269432, KB 8630"	| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
rg -z  "Master initialization took longer than" -g "acroplos.out*"								| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt

echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "Detecting if an image file is not present which is leading to image list failing in UI"	| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
echo "###########################"																| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt
rg -z  "failed with NFS3ERR_NOENT" -g "catalog.out*"											| tee  -a ~/tmp/$CASE_NUM/acropolis_check.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "CASSANDRA_MON_HEALTH_WARNINING"															| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z  "Attempting repair of local node due to health warnings received from cassandra"  -g "cassandra_monitor.*" | tee -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z  "Caught Timeout exception while waiting for paxos write response"  -g "system.log*"		| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "Detecting if cassandra skipped scans"														| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z  "Skipping scans for cf: "  -g "dynamic_ring_changer.*"									| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "Displays critical events"																	| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z  "Skipping row DecoratedKey"  -g "system.log*"											| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt
rg -z  "Fatal exception in thread"  -g "system.log*"											| tee -a ~/tmp/$CASE_NUM/cassandra_check.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/aplos_check.txt
echo "Aplos LDAP login failure  "																| tee -a ~/tmp/$CASE_NUM/aplos_check.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/aplos_check.txt
rg -z  "This search operation has checked the maximum of 10000 entries for matches"  -g "aplos.out*"	| tee -a ~/tmp/$CASE_NUM/aplos_check.txt
rg -z  "'desc': 'Bad search filter'"  -g "aplos.out*"											| tee -a ~/tmp/$CASE_NUM/aplos_check.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/aplos_check.txt
echo "SSP_MIGRATION_FAILS - KB 5919 "															| tee -a ~/tmp/$CASE_NUM/aplos_check.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/aplos_check.txt
rg -z  "Directory service update failed kunden"  -g "aplos.out*"								| tee -a ~/tmp/$CASE_NUM/aplos_check.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/aplos_check.txt
echo "remote_cluster_uuid is not known or may be unregistered "									| tee -a ~/tmp/$CASE_NUM/aplos_check.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/aplos_check.txt
rg -z  "msecs, response status: 404"  -g "aplos.out*" | grep "remote_cluster_uuid="				| tee -a ~/tmp/$CASE_NUM/aplos_check.txt


echo "###########################"																| tee -a ~/tmp/$CASE_NUM/aplos_engine.txt
echo "Aplos engine VM snapshot failure"															| tee -a ~/tmp/$CASE_NUM/aplos_engine.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/aplos_engine.txt
rg -z  "Timed out waiting for the completion of task" -g "aplos_engine.out*"					| tee -a ~/tmp/$CASE_NUM/aplos_engine.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/aplos_engine.txt
echo "PC/PE Malformed Certification failure - ENG-254057 "										| tee -a ~/tmp/$CASE_NUM/aplos_engine.txt
echo "https://opengrok.eng.nutanix.com/source/xref/euphrates-5.10.1-stable/aplos/py/aplos/lib/oauth/service_jwt_tokens.py#20"	| tee -a ~/tmp/$CASE_NUM/aplos_engine.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/aplos_engine.txt
rg -z  "IAM token validation failed with" -g "aplos*"											| tee -a ~/tmp/$CASE_NUM/aplos_engine.txt


echo "###########################"																| tee -a ~/tmp/$CASE_NUM/kernel.txt
echo "Kernel child process hung "																| tee -a ~/tmp/$CASE_NUM/kernel.txt
echo "CPU Unblock is hung.  See ENG-72597, ENG-258725 "											| tee -a ~/tmp/$CASE_NUM/kernel.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/kernel.txt
rg -z "child is hung"  -g "messages*"															| tee -a ~/tmp/$CASE_NUM/kernel.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/kernel.txt
echo "Firmware PH16 Detect - KB-6937"															| tee -a ~/tmp/$CASE_NUM/kernel.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/kernel.txt
rg -z "LSISAS3008: FWVersion(16.00.01.00)"  -g "messages*"										| tee -a ~/tmp/$CASE_NUM/kernel.txt
rg -z "mpt3sas_cm0: Command Timeout"  -g "messages*"											| tee -a ~/tmp/$CASE_NUM/kernel.txt
#rg -z "mpt3sas_cm0: sending diag reset"  -g "messages*"  | tee -a ~/tmp/$CASE_NUM/kernel.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
echo "Tracking Prism Gateway OutOfMemory Errors"												| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
rg -z  "Throwing exception from VMAdministration.getVMs"  -g "prism_gateway*"					| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
echo "RPC_PROTOBUF_ERROR"																		| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
rg -z  "InvalidProtocolBufferException: Protocol message was too large"  -g "prism_gateway*"	| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
echo "APLOS_KEY_GENERATION_FAILED"																| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
rg -z  "Generate SSL Certificate failed. Error occurred while writing the private Key"  -g "prism_gateway*"	| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
echo "CLUSTER_NOT_REACHABLE"																	| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
rg -z  "Failed to write Zeus data java.lang.IllegalStateException: cluster not reachable"  -g "prism_gateway*"	| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
echo "Backups failing due to conflicting files"       											| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt
rg -z  "Aborting the operation due to conflicting files"  -g "prism_gateway*"					| tee -a ~/tmp/$CASE_NUM/prism_gateway.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/DELL_NIC_FW_ENG296333.txt
echo "Checking for ENG-296333 AHV NIC FW issue on DELL HW"										| tee -a ~/tmp/$CASE_NUM/DELL_NIC_FW_ENG296333.txt
echo "version 2.9.21 might be trouble + N7K switch"												| tee -a ~/tmp/$CASE_NUM/DELL_NIC_FW_ENG296333.txt
echo "AHV .301 is fine since it has old FW"														| tee -a ~/tmp/$CASE_NUM/DELL_NIC_FW_ENG296333.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/DELL_NIC_FW_ENG296333.txt
rg -z "Network Driver - version" -g "dmesg" | grep i40e											| tee -a ~/tmp/$CASE_NUM/DELL_NIC_FW_ENG296333.txt

#echo "###########################"																| tee -a ~/tmp/$CASE_NUM/ENG-281158.txt
#echo "AOS 5.11.2 local user delete issue"														| tee -a ~/tmp/$CASE_NUM/ENG-281158.txt
#echo "Checking for ENG-281158 all local accounts removed"										| tee -a ~/tmp/$CASE_NUM/ENG-281158.txt
#echo "###########################"																| tee -a ~/tmp/$CASE_NUM/ENG-281158.txt
#rg -z "DELETE" -g "client_tracking.log*"														| tee -a ~/tmp/$CASE_NUM/ENG-281158.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/ISB-106-2020.txt
echo "Broadcom (LSI) SAS3008 Storage Controller Instability"									| tee -a ~/tmp/$CASE_NUM/ISB-106-2020.txt
echo "version PH16.00.01.00 is problematic."													| tee -a ~/tmp/$CASE_NUM/ISB-106-2020.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/ISB-106-2020.txt
rg -z "LSISAS3008" -g "dmesg*" | grep "16.00.01.00"												| tee -a ~/tmp/$CASE_NUM/ISB-106-2020.txt
rg -z "mpt3sas_cm0: Command Timeout" -g "dmesg*"												| tee -a ~/tmp/$CASE_NUM/ISB-106-2020.txt

echo "###########################"																| tee -a ~/tmp/$CASE_NUM/ISB-108-2020.txt
echo "Ergon task limit and its impact AOS"														| tee -a ~/tmp/$CASE_NUM/ISB-108-2020.txt
echo "Memory limit ISB-108-2020"																| tee -a ~/tmp/$CASE_NUM/ISB-108-2020.txt
echo "###########################"																| tee -a ~/tmp/$CASE_NUM/ISB-108-2020.txt
rg -z "ergon_gen_task_tree_db failed with" -g "ergon.*"											| tee -a ~/tmp/$CASE_NUM/ISB-108-2020.txt
rg -z "killed as a result of limit of" -g "messages*"	| grep -v "stopped searching binary file"	| tee -a ~/tmp/$CASE_NUM/ISB-108-2020.txt

#echo "#############################################"
#echo "21. FATAL log check $filter ."
#echo "#############################################"
#sleep 2
#filter=F`(date '+%m%d')`
#rg -z $filter .

echo "#############################################"
echo "sharepath info for engineering"
echo "#############################################"
chmod 777 -R ~/shared/$CASE_NUM
cd ~/shared/$CASE_NUM/
sharepath
sleep 2
