sh.enableSharding( "styxmail" )
sh.shardCollection( "styxmail.styxlog", { "area" : 1, "_id" : 1 } )