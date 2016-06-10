#!/bin/bash

set -eo pipefail

i=1
while read p; do
	NODE=$(printf %02d "${i}")
  	NAME=$(echo $p | cut -d / -f2)
  	echo "Create Deployment on machine ${NAME} (node${NODE})..."
  	kubectl create -f ./build/node${NODE}-deployment.yaml
  	i=$((i+1))
done < ./temp/nodefile
