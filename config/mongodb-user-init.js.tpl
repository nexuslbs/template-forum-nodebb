// Rendered by scripts/lib.sh from config/mongodb-user-init.js.tpl into
// runtime/mongo/mongodb-user-init.js. The mongo image runs this ONLY on the
// first initialization of an empty data directory.
//
// This replicates the official NodeBB/NodeBB install/docker/mongodb-user-init.js:
// MONGO_INITDB_ROOT_* creates a ROOT user in the `admin` database, but NodeBB
// builds its connection string as mongodb://user:pass@host/db and therefore
// authenticates against its OWN database. A database user must exist there too.
db.createUser({
  user: "__NODEBB_DB_USER__",
  pwd: "__NODEBB_DB_PASSWORD__",
  roles: [
    { role: "readWrite", db: "__NODEBB_DB_NAME__" },
    { role: "clusterMonitor", db: "admin" }
  ]
});
