const sql = require('mssql');
const { db } = require('./config');

let poolPromise = null;

/** One shared connection pool for the whole process. */
function getPool() {
  if (!poolPromise) {
    const cfg = {
      server: db.server,
      database: db.database,
      user: db.user,
      password: db.password,
      options: {
        encrypt: db.encrypt,
        trustServerCertificate: db.trustCert,
        enableArithAbort: true,
        ...(db.instance ? { instanceName: db.instance } : {}),
      },
      pool: { max: 20, min: 2, idleTimeoutMillis: 30000 },
      connectionTimeout: 15000,
      requestTimeout: 120000,
    };
    if (!db.instance) cfg.port = db.port; // port and instanceName are mutually exclusive
    poolPromise = new sql.ConnectionPool(cfg).connect().catch((e) => {
      poolPromise = null;
      throw e;
    });
  }
  return poolPromise;
}

module.exports = { sql, getPool };
