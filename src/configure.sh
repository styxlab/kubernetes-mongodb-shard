#!/bin/bash

set -eo pipefail

NODES=$1 && [ -z "${1}" ] && NODES="3" || true

echo
echo "Please supply some important configuration parameters below:"
echo "============================================================"
read -p "SSH user for cluster access [root]: " SSHUSER
[ -z "$SSHUSER" ] && SSHUSER="root" || true
read -p "SSH port for cluster access [22]: " SSHPORT
[ -z "$SSHPORT" ] && SSHPORT="22" || true
read -p "Root directory for your mongodb data [/data]: " BASEDIR
[ -z "$BASEDIR" ] && BASEDIR="/data" || true
read -p "Number of nodes for your shard [${NODES}]: " CFGNODES
[ -z "$CFGNODES" ] && CFGNODES=$NODES || true
echo
