#!/bin/bash

source "$(dirname $0)/common.sh"

node=$1

run_or_exit "$node leave swarm" "docker-machine ssh $node docker swarm leave"

