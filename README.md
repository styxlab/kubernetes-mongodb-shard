# kubernetes-mongodb-shard
Deploy a mongodb sharded cluster on kubernetes. 

##Prerequisites
- A Kubernetes cluster with at least 3 scheduable nodes.

##Features:
- Configurable number of shards, replicas, config servers and mongos
- Shard members and data replicas are distributed evenly on available nodes
- Storage is directly allocated on each node
- All mongo servers are combined into one kubernetes pod per node
- Services are setup which can be consumed upstream

##Description:
Setting up mongodb shard on kubernetes is easy with this repo. kubectl 
is used to determine the number of nodes in your kubernetes cluster
and the provided shell script `generate.sh` creates one kubernetes .yaml
as well as the neccessary .js config scripts. Finally, the
shard is created by executing the .yaml files and applying the
config files.

These scripts span an entire sharded mongodb database on both small
clusters with a minimum of 3 nodes and very large clusters with
100+ nodes.

Great care was taken to distribute data accross the cluster to
maximize data redundancy and high availability. In addition we
bind disk space with the kubernetes hostPath option in order
to maximize I/O throughput.

This is the first commit, so please feel free to improve this space.

##Todos:
- EmptyDir option
