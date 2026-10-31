require('dotenv').config();

const bool = (v, d) => (v === undefined || v === '' ? d : String(v).toLowerCase() === 'true');

module.exports = {
  port: +process.env.PORT || 5000,
  isProd: process.env.NODE_ENV === 'production',
  jwtSecret: process.env.JWT_SECRET || 'dev-only-change-me',
  jwtExpires: process.env.JWT_EXPIRES || '8h',
  corsOrigin: (process.env.CORS_ORIGIN || 'http://localhost:3000').split(',').map((s) => s.trim()),
  maxRows: +process.env.MAX_ROWS || 100000,
  optionsCacheSeconds: +process.env.OPTIONS_CACHE_SECONDS || 60,
  db: {
    server: process.env.DB_SERVER || 'localhost',
    instance: process.env.DB_INSTANCE || '',
    port: process.env.DB_PORT ? +process.env.DB_PORT : 1433,
    database: process.env.DB_NAME || 'ReportingDB',
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    encrypt: bool(process.env.DB_ENCRYPT, false),
    trustCert: bool(process.env.DB_TRUST_CERT, true),
  },
};
