# kubernetes-mongodb-shard
Deploy a mongodb sharded cluster on kubernetes. 

Prerequisite
- A Kubernetes cluster with at least 3 scheduable nodes.

Features:
- Replicas and shards are distributed evenly on the nodes
- Storage is directly allocated on each node
- Logical units are combined into pods
- Services are setup which can be consumed upstream

Limitations:
- The mongodb shard will only populate 3 nodes. The scripts need to be extended for more nodes.
