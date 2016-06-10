rs.initiate()
cfg = rs.conf()
cfg.members[0].host = "__PRIMARY_SVC_ADDR__"
cfg.members[0].priority = 5
rs.reconfig(cfg, {force: true})
