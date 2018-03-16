#!/bin/bash

source "$(dirname $0)/common.sh"

export DIGITALOCEAN_ACCESS_TOKEN=$DO_TOKEN
export DIGITALOCEAN_SIZE=2gb
export DIGITALOCEAN_PRIVATE_NETWORKING=true

for i in 1 2 3; do 
    run_or_exit "Creating node-$i" "docker-machine create -d digitalocean node-$i"	
done

manager_ip=$(docker-machine ssh node-1 ifconfig eth1 | grep "inet addr" | cut -d ':' -f 2 | cut -d ' ' -f 1)
echo "Manager private ip: $manager_ip"

run_or_exit "Make node-1 the manager/leader" "docker-machine ssh node-1 docker swarm init --advertise-addr ${manager_ip}"

worker_token=$(docker-machine ssh node-1 docker swarm join-token worker -q)
echo "Worker token: $worker_token"

for i in 2 3; do 
    run_or_exit "Join node-$i as worker" "docker-machine ssh node-$i docker swarm join --token ${worker_token} ${manager_ip}:2377"
done

run_or_exit "List swarm nodes" "docker-machine ssh node-1 docker node ls"

run_or_exit "Creating attachable overlay network" "docker-machine ssh node-1 docker network create -d overlay --attachable core-infra"

for i in 2 3; do 
    run_or_exit "Add label to data node node-$i" "docker-machine ssh node-1 docker node update --label-add data=true node-$i"
done

echo "Done"
