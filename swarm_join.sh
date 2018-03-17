#!/bin/bash

source "$(dirname $0)/common.sh"

node=$1

manager_ip=$(docker-machine ssh node-1 ifconfig eth1 | grep "inet addr" | cut -d ':' -f 2 | cut -d ' ' -f 1)
worker_token=$(docker-machine ssh node-1 docker swarm join-token worker -q)

# run_or_exit "Join $node as worker" "docker-machine ssh node-1 docker node rm $node"
run_or_exit "Remove left node $node" "docker-machine ssh node-1 docker node rm $node"

run_or_exit "Join $node as worker" "docker-machine ssh $node docker swarm join --token ${worker_token} ${manager_ip}:2377"
run_or_exit "Add label to $node" "docker-machine ssh node-1 docker node update --label-add data=true $node"
