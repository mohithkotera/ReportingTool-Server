class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

/** Forward rejected promises from async route handlers to Express. */
const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/** Tiny TTL cache with in-flight de-duplication. */
class TtlCache {
  constructor(ttlMs) {
    this.ttl = ttlMs;
    this.map = new Map();
  }
  async wrap(key, loader) {
    const hit = this.map.get(key);
    if (hit && hit.exp > Date.now()) return hit.value;
    const value = Promise.resolve().then(loader);
    this.map.set(key, { exp: Date.now() + this.ttl, value });
    try {
      return await value;
    } catch (e) {
      this.map.delete(key);
      throw e;
    }
  }
  clear() {
    this.map.clear();
  }
}

module.exports = { HttpError, wrap, TtlCache };
