const jwt = require('jsonwebtoken');
const cfg = require('../config');
const users = require('../services/userService');
const { HttpError, wrap } = require('../utils/http');

/** Verifies the JWT, then re-checks the user/role in DB (cached 30s) so revocations apply quickly. */
const authenticate = wrap(async (req, _res, next) => {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) throw new HttpError(401, 'Authentication required');

  let payload;
  try {
    payload = jwt.verify(token, cfg.jwtSecret);
  } catch {
    throw new HttpError(401, 'Session expired. Please sign in again.');
  }
  const user = await users.findById(payload.sub);
  if (!user || !user.IsActive) throw new HttpError(401, 'Account is disabled or no longer exists');

  req.user = { userId: user.UserId, roleId: user.RoleId, role: user.RoleName, record: user };
  next();
});

/** Optional guard for admin-style endpoints: requireRole('Admin'). */
const requireRole = (...roles) => (req, _res, next) =>
  roles.includes(req.user.role) ? next() : next(new HttpError(403, 'Forbidden'));

module.exports = { authenticate, requireRole };
