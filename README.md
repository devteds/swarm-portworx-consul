> Find more examples and short videos on development & deployments with docker, aws etc on [devteds.com](https://devteds.com)

# Stateful Containers: Docker Swarm + Portworx + Consul

- Create Swarm Cluster of 3 nodes on digitalocean
- Run Consul Cluster on Swarm
- Make 2 of 3 nodes the data nodes (label data=true)
- Attach volumes (block storage) to data nodes
- Install and setup portworx cluster for data nodes; Use consul KV store
- Create volume and run app services (api app & database)
- Test MySQL state by toggling the data nodes on swarm cluster

*Tested on docker version Docker version 17.12.0-ce, build c97c6d6*

## Swarm Cluster

Create swarm cluster of those 3 nodes on digitalocean. Optionally, edit `swarm.sh` to change DigitalOcean droplet configs.

```
export DO_TOKEN=<DigitalOcean API Access Token>
./swarm.sh
```

**Volumes:** Create and attach volumes on digital ocean

## Consul Cluster

Refer https://github.com/devteds/swarm-consul

```
eval $(docker-machine env node-1)
docker stack deploy -c consul.yml kv
```

Verify the stack & agents/containers. There may be some errors before all the nodes in the consul cluster start up and complete leader election. Give it about 30 seconds to gossip and complete leader election.

```
docker stack ps -f "desired-state=running" kv
docker service logs kv_server-bootstrap
docker service logs kv_server
docker service logs kv_client
docker service inspect kv_server-bootstrap
```

Consul UI & Catalog

```
open http://$(docker-machine ip node-1):8500/ui
curl http://$(docker-machine ip node-1):8500/v1/catalog/datacenters
curl http://$(docker-machine ip node-1):8500/v1/catalog/nodes
```

Test Consul CLI - https://github.com/devteds/swarm-consul/blob/master/README.md#test-consul-cli

## Cloud (Digital Ocean)

- Add volumes of 5G to the data nodes (node-2 & node-3)
  - Login to DO > Droplets > node-2|node-3 > Volumes > Add Volume > 5GB > Create Volume
- Test new volume mount on the nodes using `lsblk`
- New volumes should appear as /dev/sda (or `sda` with type as disk) in the output of `lsblk`

```
docker-machine ssh node-2 lsblk
docker-machine ssh node-3 lsblk
```

Sample output

```
NAME    MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sda       8:0    0    5G  0 disk
vda     253:0    0   40G  0 disk
├─vda1  253:1    0 39.9G  0 part /
├─vda14 253:14   0    4M  0 part
└─vda15 253:15   0  106M  0 part /boot/efi
```

## Portworx

- Install NTP on all swarm nodes
- Install portworx on the nodes that are labelled `data`
- Create new px volume cluster
- Restart daemon and enable/start px

```
#./px_setup.sh <CLUSTER ID> <BLOCK DEVICE>
./px_setup.sh C123 /dev/sda
```

Give it a few minutes and verify,

```
docker-machine ssh node-2 /opt/pwx/bin/pxctl status
docker-machine ssh node-3 /opt/pwx/bin/pxctl status
```

Output should start with `Status: PX is operational` and the details of the block device.

Also verify consul key/value,

```
open "http://$(docker-machine ip node-1):8500/ui/#/dc1/kv/"
```

## Application Stack

API service and a datbase service that use portworx volume. Check the `db` service in `app.yml` to learn how the portworx volume is created and used.

```
eval $(docker-machine env node-1)
docker stack deploy -c app.yml app
```

Verify the stack & containers. Current State should be "Running x ....s"

```
docker stack ps -f "desired-state=running" app
docker service logs app_db
docker service logs app_api

docker service inspect app_db
docker service inspect app_api

# Verify node-2 & node-3 has volume 'app_mydb'
docker-machine ssh node-2 docker volume ls
docker-machine ssh node-3 docker volume ls
```

When all the 3 containers of `app` stack are running, create tables and populate some data (db:migrate & db:seed). Run on one of the app containers.

```
eval $(docker-machine env node-1)
api_node=$(docker stack ps -f "desired-state=running" app | grep app_api | awk '{print $4}' | head -1)
eval $(docker-machine env "$api_node")
api_container=$(docker ps -a | grep app_api | awk '{print $1}' | head -1)
docker exec -it $api_container rails db:migrate
docker exec -it $api_container rails db:seed
```

Verify the application

```
open http://$(docker-machine ip node-1):3000/notes
```

Webpage should list all the notes records and you should be able view or edit.

## Test PX behavior

Let the node that run mysql container (or db service container), leave swarm cluster

```
docker stack ps -f "desired-state=running" app

# Let's make the db node leave swarm
node=$(docker stack ps -f "desired-state=running" app | grep app_db | awk '{print $4}' | head -1)
./swarm_leave. $node

# Check swarm nodes & status
docker-machine ssh node-1 docker node ls

# Give it a couple of seconds and see the sttus.
docker stack ps -f "desired-state=running" app
```

Keep checking the stack status. 

The app_db service container will have a brief outage and start up on the other data node. That will initially be in "Preparing .." and the application should work when the Current State of that new container changes to "Running x ....s"

```
docker stack ps -f "desired-state=running" app
open http://$(docker-machine ip node-1):3000/notes
```

Now try switching the data node

```
docker stack ps -f "desired-state=running" app

# Join back to swarm
./swarm_join.sh $node

# Check swarm nodes & status
docker-machine ssh node-1 docker node ls

# Let's make the current active db node leave swarm
node=$(docker stack ps -f "desired-state=running" app | grep app_db | awk '{print $4}' | head -1)
./swarm_leave. $node

# Check swarm nodes & status
docker-machine ssh node-1 docker node ls

# Give it a couple of seconds and see the sttus.
docker stack ps -f "desired-state=running" app
```

Database container now should switch to other data node and application should still work.


## Verify Portworx & useful commands

```
# journalctl
docker-machine ssh node-2 journalctl -f -u portworx

docker-machine ssh node-2 systemctl daemon-reload

# status | stop | enable | reenable | start
docker-machine ssh node-2 systemctl status portworx

# pxctl
docker-machine ssh node-2 /opt/pwx/bin/pxctl status
docker-machine ssh node-2 /opt/pwx/bin/pxctl c l
docker-machine ssh node-2 /opt/pwx/bin/pxctl v l
```

# Resources

- https://docs.portworx.com/scheduler/docker/swarm.html
- https://docs.portworx.com/runc/index.html
- https://docs.portworx.com/manage/volumes.html
- https://docs.portworx.com/scheduler/docker/install-swarm.html
- https://docs.portworx.com/maintain/etcd.html
- https://github.com/portworx/px-docs/blob/gh-pages/etcd/ansible/index.md
- http://install.portworx.com:8080
- http://install.portworx.com:8080?type=dock&stork=false

**Fetch latest enterprise version**

```
curl -fsSL 'http://install.portworx.com:8080?type=dock&stork=false' | awk '/image: / {print $2}'
``` 

## Create Volume on one of the PX cluster nodes

```
Creating stack will create the new volume. ANother option is to create manually and make the volume external true.
docker volume create -d pxd --name mydb --opt size=3G
```

# More

For more code samples and short video tutorials on development & development with docker & cloud,

- https://devteds.com
- https://github.com/devteds
- https://www.youtube.com/c/ChandraShettigar
