const crypto = require('crypto');

/** MD5 hex digest (lower-case) - matches LOWER(CONVERT(VARCHAR(32), HASHBYTES('MD5', pwd), 2)) in SQL Server. */
const md5 = (text) => crypto.createHash('md5').update(String(text), 'utf8').digest('hex');

/** Constant-time comparison of two hex digests. */
function safeEqual(a, b) {
  const x = Buffer.from(String(a || '').toLowerCase());
  const y = Buffer.from(String(b || '').toLowerCase());
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

module.exports = { md5, safeEqual };
