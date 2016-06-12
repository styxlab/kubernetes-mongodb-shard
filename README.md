# kubernetes-mongodb-shard
Deploy a mongodb sharded cluster on kubernetes. 

##Prerequisites
- A Kubernetes cluster with at least 3 scheduable nodes.

##Features
- Configurable number of shards, replicas, config servers and mongos
- Shard members and data replicas are distributed evenly on available nodes
- Storage is directly allocated on each node
- All mongo servers are combined into one kubernetes pod per node
- Services are setup which can be consumed upstream
- Official mongodb docker image is used without modifications

##Description
Setting up mongodb shard on kubernetes is easy with this repo. kubectl 
is used to determine the number of nodes in your kubernetes cluster
and the provided shell script `generate.sh` creates one kubernetes `.yaml`
per pod as well as the neccessary `.js` config scripts. Finally, the
shard is created by executing the `.yaml` files and applying the
config files.

These scripts span an entire sharded mongodb database on both small
clusters with a minimum of 3 nodes and very large clusters with
100+ nodes.

Great care is taken to distribute data accross the cluster to
maximize data redundancy and high availability. In addition we
bind disk space with the kubernetes hostPath option in order
to maximize I/O throughput.

##Usage
```
$ git clone https://github.com/styxlab/kubernetes-mongodb-shard.git
$ cd kubernetes-mongodb-shard
$ make build
```
All needed files can be found in the `build` folder. You should find one
`.yaml` file for each node of you cluster and a couple of `.js`
files that will configure the mongodb shard. Finally, you
need to execute these files on your kubernetes cluster:
```
$ make run
```
##Verify
If all goes well, you will see that all deployments are up and running. For a 3 node shard, a typical
output is shown below.
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
You can now connect to one of the mogos and inspect the status of the shard:
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

##Consume
The default configurations configures one mongos service per node which can be used to connect
to your shard from any other application on your kubernetes cluser:
```
$ kubectl get svc -l role="mongoshard"
NAME             CLUSTER-IP   EXTERNAL-IP   PORT(S)                                             AGE
mongodb-node01   10.3.0.175   <none>        27019/TCP,27018/TCP,27017/TCP,27020/TCP,27021/TCP   1d
mongodb-node02   10.3.0.13    <none>        27019/TCP,27018/TCP,27017/TCP,27020/TCP,27021/TCP   1d
mongodb-node03   10.3.0.47    <none>        27019/TCP,27018/TCP,27017/TCP,27020/TCP,27021/TCP   1d
```



##Todos:
- EmptyDir option
