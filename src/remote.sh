#!/bin/bash

set -eo pipefail

REMOTEPORT=$2 && [ -z "${2}" ] && REMOTEPORT="22"

function sshCall(){
	ssh -p $REMOTEPORT core@$1 $2 </dev/null
}
function execRemote(){
	FILE=${1}
	SHARDS=${2}
	i=1
	while read pp; do
		ii=$(printf %02d "${i}")
  		HOSTNAME=$(echo $pp | cut -d / -f2)
  		echo "Executing commands on ${HOSTNAME}..."
  		sshCall $HOSTNAME "sudo mkdir -p /enc/mongodb/db-cfg"
  		echo "Ensure correct kernel settings for mongodb..."
  		sshCall $HOSTNAME 'sudo /bin/bash -c "echo never > /sys/kernel/mm/transparent_hugepage/enabled"'
  		sshCall $HOSTNAME 'sudo /bin/bash -c "echo never > /sys/kernel/mm/transparent_hugepage/defrag"'
  		for j in $(seq ${SHARDS}); do
  			RSNUM=$(printf %02d ${j})
  			echo "Create directories for replica set ${RSNUM}."
  			sshCall $HOSTNAME "sudo mkdir -p /enc/mongodb/db-rs${RSNUM}"
  		done
  		i=$((i+1))
	done < "$FILE"
}

if [ -z "$1" ]; then
	echo "Please provide the number of shards: sh remote.sh <shards>"
	exit 1
fi
echo "Number of Shards / Replication Sets: ${1}"
if [ -e ./temp/nodefile ]; then 
	execRemote "./temp/nodefile" $1
else
	echo "You need to run generate.sh first."
	exit 1
fi