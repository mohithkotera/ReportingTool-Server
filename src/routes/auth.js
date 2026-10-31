const router = require('express').Router();
const jwt = require('jsonwebtoken');
const rateLimit = require('express-rate-limit');
const cfg = require('../config');
const users = require('../services/userService');
const { md5, safeEqual } = require('../utils/crypto');
const { authenticate } = require('../middleware/auth');
const { HttpError, wrap } = require('../utils/http');

const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { message: 'Too many login attempts. Try again in a few minutes.' },
});

router.post(
  '/login',
  loginLimiter,
  wrap(async (req, res) => {
    const { username, password } = req.body || {};
    if (!username || !password) throw new HttpError(400, 'Username and password are required');

    const user = await users.findByUsername(String(username).trim());
    const ok = user && user.IsActive && safeEqual(md5(password), user.PasswordHash);
    if (!ok) throw new HttpError(401, 'Invalid username or password');

    await users.touchLogin(user.UserId);
    const token = jwt.sign({ sub: user.UserId }, cfg.jwtSecret, { expiresIn: cfg.jwtExpires });
    res.json({ token, user: users.toPublic(user) });
  })
);

router.get(
  '/me',
  authenticate,
  wrap(async (req, res) => res.json(users.toPublic(req.user.record)))
);

module.exports = router;
