#!/bin/bash

set -eo pipefail

function cleanUp(){
	rm -rf *.yaml
	rm -rf *.js
	rm -rf ./tmp
	rm -rf ./build
	mkdir -p ./tmp/yaml
	mkdir -p ./tmp/js
	mkdir -p ./build
}

cleanUp