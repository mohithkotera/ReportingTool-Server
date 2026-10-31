const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const compression = require('compression');
const cfg = require('./config');
const { getPool } = require('./db');

const app = express();
app.disable('x-powered-by');
app.use(helmet());
app.use(cors({ origin: cfg.corsOrigin }));
app.use(compression({ threshold: 1024 })); // gzip: 10k-row results shrink ~8x
app.use(express.json({ limit: '1mb' }));

app.get('/api/health', async (_req, res) => {
  try {
    await (await getPool()).request().query('SELECT 1 AS ok');
    res.json({ status: 'ok' });
  } catch (e) {
    res.status(503).json({ status: 'db_unavailable', message: e.message });
  }
});

app.use('/api/auth', require('./routes/auth'));
app.use('/api/reports', require('./routes/reports'));

app.use((_req, res) => res.status(404).json({ message: 'Not found' }));

// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  const status = err.status || 500;
  if (status >= 500) console.error(err);
  const message = status >= 500 && cfg.isProd ? 'Something went wrong on the server' : err.message;
  res.status(status).json({ message });
});

app.listen(cfg.port, () => {
  console.log(`Reporting API listening on http://localhost:${cfg.port}`);
  getPool()
    .then(() => console.log(`Connected to SQL Server (${cfg.db.server}/${cfg.db.database})`))
    .catch((e) => console.error('SQL Server connection failed:', e.message));
});
