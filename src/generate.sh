#!/bin/bash

set -eo pipefail

# Layout Description
# columns - nodes
# rows    - shards
# 0 - empty
# 1 - replica set - primary   (rsp)
# 2 - replica set - secondary (rss)
# 3 - replica set - arbiter   (arb)
#
# Examples
#
# 3nodes, 3 shards, 2 shards per node, 1 arbiter
# 123
# 231
# 312
#
# 4nodes, 4 shards, 2 shards per node, 1 arbiter
# 1230
# 2301
# 3012
# 0123
#
# 5nodes, 5 shards, 2 shards per node, 1 arbiter
# 12300
# 23001
# 30012
# 00123
# 01230

#global vars
CONFIG_SERVERS_SERVICES=""
CONFIG_SERVERS_SERVICES_JS=""

# Helper Functions
function cleanUp(){
	rm -rf *.yaml
	rm -rf *.js
	rm -rf ./tmp
	rm -rf ./build
	mkdir -p ./tmp/yaml
	mkdir -p ./tmp/js
	mkdir -p ./build
}
function getNodeNames(){
	i=1
	while read p; do
		ii=$(printf %02d "${i}")
  		echo $p | cut -d / -f2 > "${2}/node${ii}"
  		i=$((i+1))
	done <$1
}
function rotateAxis(){
	axis=$2 && [ -z "$2" ] && axis=1
	left=$(echo $1 | cut -b $((axis+1))-)
	right="" && [ ! "$axis" = "0" ] && right=$(echo $1 | cut -b 1-${axis}) 
	echo "${left}${right}"
}
function validateConstraints(){
	[ $1 -lt $2 ] && (echo "Value $1 must greater or equal $2"; exit 1) || true
	[ $1 -gt $3 ] && (echo "Value $1 must less or equal $3"; exit 1) || true
}
function getPattern(){
	NODEGAPS=$(($1 - $2))
	GAPPATTERN=""
	if [ "${NODEGAPS}" -gt "0" ]; then
		GAPPATTERN=$(printf %0${NODEGAPS}d "0")
	fi
	ARBITER=""
	if [ "${3}" -gt "0" ]; then
		ARBITER="3"
	fi
	SECONDARIES=""
	SECNUMS=$(($2-$3-1))
	if [ "${SECNUMS}" -gt "0" ]; then
		SECONDARIES=$(printf %0${SECNUMS}d "2")
	fi
	echo "1${SECONDARIES}${ARBITER}${GAPPATTERN}"
}
function getRole(){
	echo $1 | cut -b 1
}
function getPortShift(){
	IDX1=$((2 * $1 - 2))
	echo "${RSSADD:${IDX1}:2}"
}
function addPortShift(){
	VAL=$(getPortShift $1)
	VAL=$(printf %02d $(($VAL + 1)))
	AXIS1=$(( 2 * $1 - 2))
	AXIS2=$((${#RSSADD} - $AXIS1 ))
	AFTER=$(rotateAxis $RSSADD $AXIS1 | cut -b 3-)
	RSSADD=$(rotateAxis "${VAL}${AFTER}" ${AXIS2})
}
function getSpec(){
	NODENUM=$(printf %02d ${1})
	RSNUM=$(printf %02d ${2})
	ROLE=$(getRole ${3})
	if [ "${ROLE}" = "1" ]; then
		PORT=$RSPPORT
		echo "rsp${RSNUM}-node${NODENUM}-port${PORT}"
	fi
	if [ "${ROLE}" = "2" ]; then
		addPortShift $NODENUM
		SHIFT=$(getPortShift $NODENUM)
		PORT=$(($RSPPORT+$SHIFT))
		echo "rss${RSNUM}-node${NODENUM}-port${PORT}"
	fi
	if [ "${ROLE}" = "3" ]; then
		PORT=$ARBPORT
		echo "arb${RSNUM}-node${NODENUM}-port${PORT}"
	fi
}
function getCfg(){
	[ $1 -gt 1 ] && (echo "Not yet implemented. Change to $CFG_PER_CLUSTER to 1."; exit 1) || true
	echo "cfg${1}-node${2}-port${CFGPORT}"
}
function addShard(){
	PREFIX=$(echo $1 | cut -b 1-3)
	if [ "${PREFIX}" = "rsp" ]; then
		RSNUM=$(echo $1 | cut -b 4-5)
		NODENUM=$(echo $1 | cut -b 11-12)
		echo "sh.addShard(\"rs${RSNUM}/mongodb-node${NODENUM}.default.svc.cluster.local:${RSPPORT}\")" \
			>> ./build/shard-init.js
	fi
}
function genYamlFromTemplates(){
	TEMPLATE_PATH="./yaml-templates"
	JS_PATH="./js-templates"
	NODENUM=$(echo $1 | cut -b 11-12)
	NODESELECTOR=$(cat "./tmp/node${NODENUM}")
	OUTFILE="./tmp/yaml/node${NODENUM}-partial.yaml"
	SVC_OUTFILE="./tmp/yaml/svc${NODENUM}-partial.yaml"
	if [ ! -e "$OUTFILE" ]; then
		cat "${TEMPLATE_PATH}/nodeXX-template.yaml" \
			| sed "s|__NODENUM__|${NODENUM}|g" \
			| sed "s|__NODESELECTOR__|${NODESELECTOR}|g" \
			| sed "/##/d" \
			> $OUTFILE
		cat "${TEMPLATE_PATH}/svcXX-template.yaml" \
			| sed "s|__NODENUM__|${NODENUM}|g" \
			| sed "/##/d" \
			> $SVC_OUTFILE	
	fi
	RSID=$(echo $1 | cut -b 1-2)
	if [ "$RSID" = "rs" ] || [ "$RSID" = "ar" ];  then
		RSID=$(echo $1 | cut -b 1-3)
		RSNUM=$(echo $1 | cut -b 4-5)
		PORT=$(echo $1 | cut -b 18-22)
		OUTFILE="./tmp/yaml/node${NODENUM}-${RSID}${RSNUM}-partial.yaml"
		cat "${TEMPLATE_PATH}/rsXX-template.yaml" \
			| sed "s|__NODENUM__|${NODENUM}|g" \
			| sed "s|__RSNUM__|${RSNUM}|g" \
			| sed "s|__PORT__|${PORT}|g" \
			| sed "s|__RSID__|${RSID}|g" \
			| sed "s|__VERSION__|${VERSION}|g" \
			| sed "/##/d" \
			> $OUTFILE
		OUTFILE="./tmp/yaml/node${NODENUM}-db${RSNUM}-volumes.yaml"
		cat "${TEMPLATE_PATH}/volumes-template.yaml" \
		    | sed "s|__BASEDIR__|${BASEDIR}|g" \
			| sed "s|__RSNUM__|${RSNUM}|g" \
			| sed "/##/d" \
			> $OUTFILE
		if [ "$RSID" = "rsp" ]; then
			OUTFILE="./tmp/js/node${NODENUM}-rs${RSNUM}-pri.js"
			PRIMARY_SVC_ADDR="mongodb-node${NODENUM}.default.svc.cluster.local:${PORT}"
			cat "${JS_PATH}/rsXX-pri-template.js" \
				| sed "s|__PRIMARY_SVC_ADDR__|${PRIMARY_SVC_ADDR}|g" \
				| sed "/##/d" \
				> $OUTFILE
		fi
		if [ "$RSID" = "rss" ]; then
			OUTFILE="./tmp/js/node${NODENUM}-rs${RSNUM}-sec.js"
			SECONDARY_SVC_ADDR="mongodb-node${NODENUM}.default.svc.cluster.local:${PORT}"
			cat "${JS_PATH}/rsXX-sec-template.js" \
				| sed "s|__SECONDARY_SVC_ADDR__|${SECONDARY_SVC_ADDR}|g" \
				| sed "/##/d" \
				> $OUTFILE
		fi
		if [ "$RSID" = "arb" ]; then
			OUTFILE="./tmp/js/node${NODENUM}-rs${RSNUM}-arb.js"
			ARBITER_SVC_ADDR="mongodb-node${NODENUM}.default.svc.cluster.local:${PORT}"
			cat "${JS_PATH}/rsXX-arb-template.js" \
				| sed "s|__ARBITER_SVC_ADDR__|${ARBITER_SVC_ADDR}|g" \
				| sed "/##/d" \
				> $OUTFILE
		fi
	fi
	if [ "$RSID" = "cf" ]; then
		RSID=$(echo $1 | cut -b 1-3)
		RSNUM=$(echo $1 | cut -b 4-5)
		PORT=$(echo $1 | cut -b 18-22)
		OUTFILE="./tmp/yaml/node${NODENUM}-${RSID}${RSNUM}-partial.yaml"
		cat "${TEMPLATE_PATH}/cfgXX-template.yaml" \
			| sed "s|__NODENUM__|${NODENUM}|g" \
			| sed "s|__RSNUM__|${RSNUM}|g" \
			| sed "s|__PORT__|${PORT}|g" \
			| sed "s|__RSID__|${RSID}|g" \
			| sed "s|__VERSION__|${VERSION}|g" \
			| sed "/##/d" \
			> $OUTFILE
		ID=$((${NODENUM}-1))
		CONFIG_SERVERS_SERVICES="${CONFIG_SERVERS_SERVICES},mongodb-node${NODENUM}.default.svc.cluster.local:${PORT}"
		CONFIG_SERVERS_SERVICES_JS="${CONFIG_SERVERS_SERVICES_JS},\n\t\t{ _id: ${ID}, host: \"mongodb-node${NODENUM}.default.svc.cluster.local:${PORT}\" }"
	fi
	if [ "$RSID" = "mg" ]; then
		RSID=$(echo $1 | cut -b 1-3)
		MSGNUM=$(echo $1 | cut -b 4-5)
		PORT=$(echo $1 | cut -b 18-22)
		OUTFILE="./tmp/yaml/node${NODENUM}-${RSID}${MSGNUM}-partial.yaml"
		cat "${TEMPLATE_PATH}/mgsXX-template.yaml" \
			| sed "s|__NODENUM__|${NODENUM}|g" \
			| sed "s|__MSGNUM__|${MSGNUM}|g" \
			| sed "s|__PORT__|${PORT}|g" \
			| sed "s|__RSID__|${RSID}|g" \
			| sed "s|__VERSION__|${VERSION}|g" \
			| sed "/##/d" \
			> $OUTFILE
	fi
	RSID=$(echo $1 | cut -b 1-3)
	RSNUM=$(echo $1 | cut -b 4-5)
	PORT=$(echo $1 | cut -b 18-22)
	OUTFILE="./tmp/yaml/svc${NODENUM}-${RSID}${RSNUM}-port-partial.yaml"
	cat "${TEMPLATE_PATH}/svcXX-port-template.yaml" \
		| sed "s|__NODENUM__|${NODENUM}|g" \
		| sed "s|__RSNUM__|${RSNUM}|g" \
		| sed "s|__PORT__|${PORT}|g" \
		| sed "s|__RSID__|${RSID}|g" \
		| sed "/##/d" \
		> $OUTFILE
}
genFinalFromPartials(){
	YAML_PATH="./tmp/yaml"
	JS_PATH="./tmp/js"
	TEMPLATE_PATH="./yaml-templates"
	JS_TEMPLATE_PATH="./js-templates"
	#cfg01.default.svc.cluster.local:27017,cfg02.default.svc.cluster.local:27017,cfg03.default.svc.cluster.local:27017"
	CONFIG_SERVERS_SERVICES=$(echo $CONFIG_SERVERS_SERVICES | cut -b 2-)
	CONFIG_SERVERS_SERVICES_JS=$(echo $CONFIG_SERVERS_SERVICES_JS | cut -b 4-)
	for i in $(seq ${CFG_PER_CLUSTER}); do
		RSNUM=$(printf %02d ${i})
		cat ${JS_PATH}/node*-rs${RSNUM}-cfg.js \
			| sed "s|__CONFIG_SERVERS_SERVICES_JS__|${CONFIG_SERVERS_SERVICES_JS}|g" \
			> "./build/cfg${RSNUM}-init.js"
	done
	for j in $(seq ${NODES}); do
		NODENUM=$(printf %02d ${j})
		cat ${YAML_PATH}/svc${NODENUM}-partial.yaml \
			${YAML_PATH}/svc${NODENUM}-*-port-partial.yaml \
			${TEMPLATE_PATH}/separator.yaml \
			${YAML_PATH}/node${NODENUM}-partial.yaml \
			${YAML_PATH}/node${NODENUM}-arb*.yaml \
			${YAML_PATH}/node${NODENUM}-rss*.yaml \
			${YAML_PATH}/node${NODENUM}-rsp*.yaml \
			${YAML_PATH}/node${NODENUM}-cfg*.yaml \
			${YAML_PATH}/node${NODENUM}-mgs*.yaml \
			${TEMPLATE_PATH}/volumes-head.yaml \
			${YAML_PATH}/node${NODENUM}-db*-volumes.yaml \
		| sed "s|__BASEDIR__|${BASEDIR}|g" \
		| sed "s|__CONFIG_SERVERS_SERVICES__|${CONFIG_SERVERS_SERVICES}|g" \
		> "./build/node${NODENUM}-deployment.yaml"
	done
	for i in $(seq ${SHARDS}); do
		RSNUM=$(printf %02d ${i})
		NODENUM=$(ls ${JS_PATH}/node*-rs${RSNUM}-pri.js | cut -d'/' -f 4 | cut -b 5-6)
		cat ${JS_PATH}/node*-rs${RSNUM}-pri.js \
			${JS_PATH}/node*-rs${RSNUM}-sec.js \
			${JS_PATH}/node*-rs${RSNUM}-arb.js \
		> "./build/node${NODENUM}-rs${RSNUM}-init.js"
	done
}

# Ensure clean startup
cleanUp

# Gather basic config parameters
kubectl get nodes| grep -v "SchedulingDisabled" | awk '{print $1}' | tail -n +2 > ./tmp/nodefile
getNodeNames "./tmp/nodefile" "./tmp"
NODES=$(cat ./tmp/nodefile |wc -l)

# Ask for some config parameters
source src/configure.sh ${NODES}

echo "Please ensure that pods can be scheduled on all these nodes."
echo "------------------------------------------------------------"
NODES=${CFGNODES}
echo "CLUSTER NODES.....................: ${NODES}"
SHARDS=${NODES}
validateConstraints $SHARDS 1 $NODES
echo "SHARD MEMBERS.....................: ${SHARDS}"

MONGOS_PER_CLUSTER=${NODES}
echo "MONGOS PER CLUSTER................: ${MONGOS_PER_CLUSTER}"
validateConstraints $MONGOS_PER_CLUSTER 1 $NODES

CFG_PER_CLUSTER=1
echo "CONFIG SERVERS PER CLUSTER........: ${CFG_PER_CLUSTER}"

CFG_REPLICAS=${NODES}
echo "CONFIG REPLICAS PER CLUSTER.......: ${CFG_REPLICAS}"
validateConstraints $CFG_REPLICAS 1 $NODES

REPLICAS_PER_SHARD=2
echo "DATA REPLICAS PER SHARD...........: ${REPLICAS_PER_SHARD}"

ARBITER=$(((${REPLICAS_PER_SHARD} + 1) % 2  ))
echo "ARBITER PER REPLICA SET...........: ${ARBITER}"

REPLICAS=$((${REPLICAS_PER_SHARD} + ${ARBITER}))
validateConstraints $REPLICAS 1 $NODES
echo "TOTAL REPLICAS PER SHARD..........: ${REPLICAS}"

FIRSTROW=$(getPattern $NODES $REPLICAS $ARBITER)
#echo "FIRST ROW PATTERN ...........: ${FIRSTROW}"
echo "------------------------------------------------------------"
echo "SHARDED CLUSTER DATA REDUNDANCY...: ${REPLICAS_PER_SHARD}"
DISKSPACEFAC=$(echo "${SHARDS} / ${REPLICAS_PER_SHARD}" | bc -l)
DISKSPACEFAC=$(printf %.1f ${DISKSPACEFAC})
echo "DISK SPACE FACTOR ................: ${DISKSPACEFAC} (times GB per node)"
echo "------------------------------------------------------------"

MONGOSPORT="27017"
CFGPORT=$(($MONGOSPORT+1))
ARBPORT=$(($MONGOSPORT+2))
RSPPORT=$(($MONGOSPORT+3))
DOUBLENODES=$((${NODES} * 2))
RSSADD=$(printf %0${DOUBLENODES}d "0")

echo "Generate Kubernetes YAML files according to spec..."
for j in $(seq ${NODES}); do
	ROW=${FIRSTROW}
	for i in $(seq ${SHARDS}); do
		SPEC=$(getSpec $j $i $ROW $RSSADD)
		if [ ! -z "${SPEC}" ]; then
			echo "${SPEC}"
			genYamlFromTemplates $SPEC
			addShard $SPEC
		fi
		ROW=$(rotateAxis $ROW)
	done
	echo '---'
	FIRSTROW=$(rotateAxis $FIRSTROW)
done
 
echo "Config Server replicas loop..."
for j in $(seq ${CFG_PER_CLUSTER}); do
	RSNUM=$(printf %02d ${j})
	for i in $(seq ${CFG_REPLICAS}); do
		NODE=$(printf %02d ${i})
		CFG=$(getCfg ${RSNUM} ${NODE})
		echo "${CFG}"
		genYamlFromTemplates $CFG
	done
	OUTFILE="./tmp/js/node${RSNUM}-rs${RSNUM}-cfg.js"
		cat "${JS_PATH}/rsXX-cfg-template.js" \
			| sed "s|__RSNUM__|${RSNUM}|g" \
			| sed "/##/d" \
		> $OUTFILE
	echo '---'
done

echo "Mongos server loop..."
for j in $(seq ${CFG_PER_CLUSTER}); do
	RSNUM=$(printf %02d ${j})
	for i in $(seq ${MONGOS_PER_CLUSTER}); do
		NODENUM=$(printf %02d ${i})
		MGS="mgs${RSNUM}-node${NODENUM}-port${MONGOSPORT}"
		echo "${MGS}"
		genYamlFromTemplates $MGS
	done
done

genFinalFromPartials

echo 'Generate needed directories on remote server ...'
./src/remote.sh ${SHARDS} ${SSHUSER} ${SSHPORT} ${BASEDIR}
echo
echo "Successfully executed."
echo "Execute 'make run' to fire up the mongodb shard on your cluster."
