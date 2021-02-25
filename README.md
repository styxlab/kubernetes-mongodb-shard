# kubernetes-mongodb-shard
Deploy a mongodb sharded cluster on kubernetes. This works on both small clusters with a minimum of 3 nodes and large clusters with 100+ nodes.

## Prerequisites
- A Kubernetes cluster with at least 3 scheduable nodes.
- Kubernetes v1.2.3 or greater

## Features
- Configurable number of shards, replicas, config servers and mongos
- Shard members and data replicas are distributed evenly on available nodes
- Storage is directly allocated on each node
- All mongo servers are combined into one kubernetes pod per node
- Services are setup which can be consumed upstream
- Official mongodb docker image is used without modifications

## Description
Setting up a mongodb shard on kubernetes is easy with this repo. `kubectl`
is used to determine the number of nodes in your cluster
and the provided shell script `src/generate.sh` creates one kubernetes `yaml`
file per node as well as the neccessary `js` config scripts. Finally, the
shard is automatically created by executing the `yaml` files and applying the
config scripts.

Great care has been taken to distribute data accross the cluster to
maximize data redundancy and high availability. In addition we
bind disk space with the kubernetes `hostPath` option in order
to maximize I/O throughput.

Replication is achived by the built in mongodb feature rather than kubernetes
itself. However, as kubernetes knows about the desired state of your shard, it
will try to restore all services automatically should one node go down.

## Usage
```
$ git clone https://github.com/styxlab/kubernetes-mongodb-shard.git
$ cd kubernetes-mongodb-shard
$ make build
```
All needed files can be found in the `build` folder. You should find one
`yaml` file for each node of you cluster and a couple of `js`
files that will configure the mongodb shard. Finally, you
need to execute these files on your kubernetes cluster:
```
$ make run
```
## Verify
After a minute or two (depending on how fast the docker images are fetched over your network) you should see that all deployments are up and running. For a 3 node shard, a typical output is shown below.
```
$ kubectl get deployments -l role="mongoshard"
NAME                   DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
mongodb-shard-node01   1         1         1            1           1d
mongodb-shard-node02   1         1         1            1           1d
mongodb-shard-node03   1         1         1            1           1d

$ kubectl get pods -l role="mongoshard"
NAME                                    READY     STATUS    RESTARTS   AGE
mongodb-shard-node01-1358154500-wyv5n   5/5       Running   0          1d
mongodb-shard-node02-1578289992-i49fw   5/5       Running   0          1d
mongodb-shard-node03-4184329044-vwref   5/5       Running   0          1d
```
You can now connect to one of the mongos and inspect the status of the shard:
```
$ kubectl exec -ti mongodb-shard-node01-1358154500-wyv5n -c mgs01-node01 mongo
MongoDB shell version: 3.2.6
connecting to: test
mongos>
```
Type `sh.status()` at the mongos prompt:
```
mongos> sh.status()
--- Sharding Status --- 
  sharding version: {
	"_id" : 1,
	"minCompatibleVersion" : 5,
	"currentVersion" : 6,
	"clusterId" : ObjectId("575abbcb568388677e5336ef")
}
  shards:
	{  "_id" : "rs01",  "host" : "rs01/mongodb-node01.default.svc.cluster.local:27020,mongodb-node02.default.svc.cluster.local:27021" }
	{  "_id" : "rs02",  "host" : "rs02/mongodb-node01.default.svc.cluster.local:27021,mongodb-node03.default.svc.cluster.local:27020" }
	{  "_id" : "rs03",  "host" : "rs03/mongodb-node02.default.svc.cluster.local:27020,mongodb-node03.default.svc.cluster.local:27021" }
  active mongoses:
	"3.2.6" : 3
  balancer:
	Currently enabled:  yes
	Currently running:  no
	Failed balancer rounds in last 5 attempts:  0
	Migration Results for the last 24 hours: 
		No recent migrations
  databases:
	{  "_id" : "styxmail",  "primary" : "rs01",  "partitioned" : true }
```

## Consume
The default configurations configures one mongos service per node. Use one of them to connect
to your shard from any other application on your kubernetes cluster:
```
$ kubectl get svc -l role="mongoshard"
NAME             CLUSTER-IP   EXTERNAL-IP   PORT(S)                                             AGE
mongodb-node01   10.3.0.175   <none>        27019/TCP,27018/TCP,27017/TCP,27020/TCP,27021/TCP   1d
mongodb-node02   10.3.0.13    <none>        27019/TCP,27018/TCP,27017/TCP,27020/TCP,27021/TCP   1d
mongodb-node03   10.3.0.47    <none>        27019/TCP,27018/TCP,27017/TCP,27020/TCP,27021/TCP   1d
```

## Configuration Options
Configuration options are currently hard coded in `src/generate.sh`. This will be enhanced later. The following options are availabe:
```
NODES: number of cluster nodes (default: all nodes on your cluster as determined by kubectl)
SHARDS: number of shards in your mongo database (default: number of cluster nodes)
MONGOS_PER_CLUSTER: you connect to your shard through mongos (default: one per node, minimum: 1)
CFG_PER_CLUSTER: config servers per cluster (default: 1 config server, configured as a replication set)
CFG_REPLICA: number of replicas per configuration cluster (default: number of nodes)
REPLICAS_PER_SHARD: each shard is configured as a replication set (default: 2)
```

## Ports
As each pod gets one IP address assigned, each service within a pod must have a distinct port. 
As the mongos are the services by which you access your shard from other applications, the standard
mongodb port `27017` is given to them. Here is the list of port assignments:

| Service                         | Port    |
| ------------------------------- | --------|
| Mongos                          |  27017  |
| Config Server                   |  27018  |
| Arbiter (if present)            |  27019  |
| Replication Server (Primary)    |  27020  |
| Replication Server (Secondary)  |  27021  |

Usually you need not be concerned about the ports as you will only access the shard through the
standard port `27017`.

## Examples
A typical `yaml` file for one node is shown below:
```
apiVersion: v1
kind: Service
metadata:
  name: mongodb-node01 
  labels:
    app: mongodb-node01
    role: mongoshard
    tier: backend
spec:
  selector:
    app: mongodb-shard-node01
    role: mongoshard
    tier: backend 
  ports:
  - name: arb03-node01
    port: 27019
    protocol: TCP
  - name: cfg01-node01
    port: 27018
    protocol: TCP
  - name: mgs01-node01
    port: 27017
    protocol: TCP
  - name: rsp01-node01
    port: 27020
    protocol: TCP
  - name: rss02-node01
    port: 27021
    protocol: TCP

---

apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: mongodb-shard-node01
spec:
  replicas: 1
  template:
    metadata:
      labels:
        app: mongodb-shard-node01
        role: mongoshard
        tier: backend
    spec:
      nodeSelector:
        kubernetes.io/hostname: 80.40.200.130
      containers:
      - name: arb03-node01
        image: mongo:3.2
        args:
        - "--storageEngine"
        - wiredTiger
        - "--replSet"
        - rs03
        - "--port"
        - "27019"
        - "--noprealloc"
        - "--smallfiles"
        ports:
        - name: arb03-node01
          containerPort: 27019
        volumeMounts:
        - name: db-rs03
          mountPath: /data/db
      - name: rss02-node01
        image: mongo:3.2
        args:
        - "--storageEngine"
        - wiredTiger
        - "--replSet"
        - rs02
        - "--port"
        - "27021"
        - "--noprealloc"
        - "--smallfiles"
        ports:
        - name: rss02-node01
          containerPort: 27021
        volumeMounts:
        - name: db-rs02
          mountPath: /data/db
      - name: rsp01-node01
        image: mongo:3.2
        args:
        - "--storageEngine"
        - wiredTiger
        - "--replSet"
        - rs01
        - "--port"
        - "27020"
        - "--noprealloc"
        - "--smallfiles"
        ports:
        - name: rsp01-node01
          containerPort: 27020
        volumeMounts:
        - name: db-rs01
          mountPath: /data/db
      - name: cfg01-node01
        image: mongo:3.2
        args:
        - "--storageEngine"
        - wiredTiger
        - "--configsvr"
        - "--replSet"
        - configReplSet01
        - "--port"
        - "27018"
        - "--noprealloc"
        - "--smallfiles"
        ports:
        - name: cfg01-node01
          containerPort: 27018
        volumeMounts:
        - name: db-cfg
          mountPath: /data/db
      - name: mgs01-node01
        image: mongo:3.2
        command:
        - "mongos"
        args:
        - "--configdb"
        - "configReplSet01/mongodb-node01.default.svc.cluster.local:27018,mongodb-node02.default.svc.cluster.local:27018,mongodb-node03.default.svc.cluster.local:27018"
        - "--port"
        - "27017"
        ports:
        - name: mgs01-node01
          containerPort: 27017
      volumes:
      - name: db-cfg
        hostPath:
          path: /enc/mongodb/db-cfg
      - name: db-rs01
        hostPath:
          path: /enc/mongodb/db-rs01
      - name: db-rs02
        hostPath:
          path: /enc/mongodb/db-rs02
      - name: db-rs03
        hostPath:
          path: /enc/mongodb/db-rs03
```

## Layouts
In order to get an understanding on how this script distributes the different mongodb servers and replication
set on your cluster, a couple examples are shown. First, take note of the notation:

| Abbreviation |  Meaning                  |
| -------------| --------------------------|
| columns      |  nodes                    |
| rows         |  shards                   |
| -            |  no assignment            |
| rsp          |  replica set (primary)    |
| rss          |  replica set (secondary)  |
| arb          |  arbiter                  |

### 3 nodes, 3 shards, 2 shards per node, 1 arbiter

|         | node 1 |  node 2 | node 3 |
| ------- | ------ | ------- | ------ |
| shard 1 | rsp    |  rss    | arb    |
| shard 2 | rss    |  arb    | rsp    |
| shard 3 | arb    |  rsp    | rss    |

As can be seen, the secondary of a particular shard is always on a different node than the primary.
This ensures the replication feature. Also, each node does contain the same number of data stores, thus
distributing disk usage evenly accross the cluster.

### 5 nodes, 5 shards, 2 shards per node, 1 arbiter

|         | node 1 |  node 2 | node 3 | node 4 | node 5 |
| ------- | ------ | ------- | ------ | ------ | ------ |
| shard 1 | rsp    |  rss    | arb    | -      | -      |
| shard 2 | rss    |  arb    | -      | -      | rsp    |
| shard 3 | arb    |  -      | -      | rsp    | rss    |
| shard 4 | -      |  -      | rsp    | rss    | arb    |
| shard 5 | -      |  rsp    | rss    | arb    | -      |

Note that the same properties are retained for a larger cluster with 5 nodes. So, you can achieve
real horizontal scaling of your mongodb database with this technique.

## Todos
- Gather config parameters
- EmptyDir option
