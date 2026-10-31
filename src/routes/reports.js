const router = require('express').Router();
const svc = require('../services/reportService');
const { authenticate } = require('../middleware/auth');
const { HttpError, wrap } = require('../utils/http');

router.use(authenticate);

/** Loads the report only when the caller's role is assigned to it. */
async function loadAuthorized(req) {
  const id = parseInt(req.params.id, 10);
  if (!Number.isInteger(id)) throw new HttpError(400, 'Invalid report id');
  const report = await svc.getReportForRole(req.user.roleId, id);
  if (!report) throw new HttpError(403, 'You do not have access to this report');
  return report;
}

router.get('/', wrap(async (req, res) => res.json(await svc.listReportsForRole(req.user.roleId))));

router.get('/:id', wrap(async (req, res) => res.json(await svc.getMeta(await loadAuthorized(req)))));

router.post(
  '/:id/options/:param',
  wrap(async (req, res) => {
    const report = await loadAuthorized(req);
    res.json(await svc.getOptions(report, req.params.param, req.body?.params || {}));
  })
);

router.post(
  '/:id/run',
  wrap(async (req, res) => {
    const report = await loadAuthorized(req);
    res.json(await svc.runReport(report, req.body?.params || {}, req.user));
  })
);

module.exports = router;
