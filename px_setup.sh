#!/bin/bash

source "$(dirname $0)/common.sh"

for i in 1 2 3; do 
    run_or_exit "Unset timesync" "docker-machine ssh node-$i timedatectl set-ntp no"
    run_or_exit "Install ntp" "docker-machine ssh node-$i apt-get -y install ntp"
done

sleep 2

PX_DOCKER_IMAGE="portworx/px-enterprise:1.3.0"
# PX_DOCKER_IMAGE="portworx/px-dev:1.3.0"

# Install Portworx runC on node 2 & 3
for i in 2 3; do 
    eval $(docker-machine env node-$i)    
    run_or_exit "runC" "docker run --entrypoint /runc-entry-point.sh --rm -i --privileged=true  -v /opt/pwx:/opt/pwx -v /etc/pwx:/etc/pwx $PX_DOCKER_IMAGE"
done

eval $(docker-machine env --unset)


px_cluster_id=$1
storage_device=$2

echo "Cluster ID: $px_cluster_id"
echo "New Volume: $storage_device"

echo "----"

swarm_manager_private_ip=$(docker-machine ssh node-1 ifconfig eth1 | grep "inet addr" | cut -f2 -d":" | awk '{print $1}')

# Install volume on two nodes
for i in 2 3; do 
    echo "on node-$i"
    run_or_exit "px-runc install.." "docker-machine ssh node-$i /opt/pwx/bin/px-runc install -c $px_cluster_id -k consul:http://$swarm_manager_private_ip:8500 -s $storage_device"
done

# Reload daemon and enable start px
for i in 2 3; do 
    echo "on node-$i"
    run_or_exit "daemon-reload" "docker-machine ssh node-$i systemctl daemon-reload"
	sleep 10
    run_or_exit "enable portworx" "docker-machine ssh node-$i systemctl enable portworx"
	sleep 5
    run_or_exit "start portworx" "docker-machine ssh node-$i systemctl start portworx"
done

echo "done"
