const { sql, getPool } = require('../db');
const { TtlCache } = require('../utils/http');

const cache = new TtlCache(30_000); // role changes / deactivation take effect within 30s

const COLS = `u.UserId, u.Username, u.FullName, u.Email, u.IsActive, u.RoleId, u.LastLoginAt,
              r.RoleName`;

async function findByUsername(username) {
  const r = await (await getPool())
    .request()
    .input('u', sql.NVarChar(60), username)
    .query(`SELECT ${COLS}, u.PasswordHash
            FROM dbo.Users u JOIN dbo.Roles r ON r.RoleId = u.RoleId
            WHERE u.Username = @u`);
  return r.recordset[0] || null;
}

function findById(userId) {
  return cache.wrap(`u:${userId}`, async () => {
    const r = await (await getPool())
      .request()
      .input('id', sql.Int, userId)
      .query(`SELECT ${COLS}, (SELECT COUNT(*) FROM dbo.RoleReports rr
                               JOIN dbo.Reports rp ON rp.ReportId = rr.ReportId AND rp.IsActive = 1
                               WHERE rr.RoleId = u.RoleId) AS ReportCount
              FROM dbo.Users u JOIN dbo.Roles r ON r.RoleId = u.RoleId
              WHERE u.UserId = @id`);
    return r.recordset[0] || null;
  });
}

async function touchLogin(userId) {
  await (await getPool())
    .request()
    .input('id', sql.Int, userId)
    .query('UPDATE dbo.Users SET LastLoginAt = SYSUTCDATETIME() WHERE UserId = @id');
}

const toPublic = (u) => ({
  id: u.UserId,
  username: u.Username,
  fullName: u.FullName,
  email: u.Email,
  roleId: u.RoleId,
  role: u.RoleName,
  lastLoginAt: u.LastLoginAt,
  reportCount: u.ReportCount,
});

module.exports = { findByUsername, findById, touchLogin, toPublic };
