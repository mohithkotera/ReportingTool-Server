const { sql, getPool } = require('../db');
const cfg = require('../config');
const { HttpError, TtlCache } = require('../utils/http');

const defCache = new TtlCache(60_000); // report definitions (params + column config)
const optCache = new TtlCache(cfg.optionsCacheSeconds * 1000); // dropdown option lists

/* ------------------------------------------------------------------ */
/* Reports visible to a role                                           */
/* ------------------------------------------------------------------ */
async function listReportsForRole(roleId) {
  const r = await (await getPool())
    .request()
    .input('roleId', sql.Int, roleId)
    .query(`SELECT r.ReportId AS id, r.ReportName AS name, r.Description AS description,
                   r.Category AS category, r.Icon AS icon
            FROM dbo.Reports r
            JOIN dbo.RoleReports rr ON rr.ReportId = r.ReportId AND rr.RoleId = @roleId
            WHERE r.IsActive = 1
            ORDER BY r.Category, r.SortOrder, r.ReportName`);
  return r.recordset;
}

/** Returns the report only if the role is assigned to it (authorization gate). */
async function getReportForRole(roleId, reportId) {
  const r = await (await getPool())
    .request()
    .input('roleId', sql.Int, roleId)
    .input('reportId', sql.Int, reportId)
    .query(`SELECT r.ReportId, r.ReportName, r.Description, r.Category, r.Icon, r.QueryText
            FROM dbo.Reports r
            JOIN dbo.RoleReports rr ON rr.ReportId = r.ReportId AND rr.RoleId = @roleId
            WHERE r.ReportId = @reportId AND r.IsActive = 1`);
  return r.recordset[0] || null;
}

function getDefinition(reportId) {
  return defCache.wrap(`def:${reportId}`, async () => {
    const pool = await getPool();
    const [p, c] = await Promise.all([
      pool.request().input('id', sql.Int, reportId).query(
        `SELECT ParamId, ParamName, Label, ControlType, DataType, IsRequired, DefaultValue, Placeholder,
                OptionsQuery, OptionsJson, DependsOn, ColSpan
         FROM dbo.ReportParameters WHERE ReportId = @id ORDER BY SortOrder, ParamId`
      ),
      pool.request().input('id', sql.Int, reportId).query(
        `SELECT ColumnName, DisplayName, DataType, Align, Width, IsVisible, IsSummable, SortOrder
         FROM dbo.ReportColumns WHERE ReportId = @id ORDER BY SortOrder, ColId`
      ),
    ]);
    return { params: p.recordset, columns: c.recordset };
  });
}

const safeJson = (s) => {
  try {
    return s ? JSON.parse(s) : null;
  } catch {
    return null;
  }
};
const splitList = (s) => (s || '').split(',').map((x) => x.trim()).filter(Boolean);

/** What the browser needs to render the filter form (never includes SQL). */
async function getMeta(report) {
  const def = await getDefinition(report.ReportId);
  return {
    id: report.ReportId,
    name: report.ReportName,
    description: report.Description,
    category: report.Category,
    params: def.params.map((p) => ({
      name: p.ParamName,
      label: p.Label,
      type: p.ControlType,
      dataType: p.DataType,
      required: !!p.IsRequired,
      defaultValue: p.DefaultValue,
      placeholder: p.Placeholder,
      colSpan: p.ColSpan || 1,
      dependsOn: splitList(p.DependsOn),
      hasQuery: !!p.OptionsQuery,
      options: p.OptionsQuery ? null : safeJson(p.OptionsJson) || [],
    })),
  };
}

/* ------------------------------------------------------------------ */
/* Parameter binding - every value is passed as a typed SQL parameter  */
/* ------------------------------------------------------------------ */
const TYPES = {
  string: sql.NVarChar(4000),
  csv: sql.NVarChar(sql.MAX),
  int: sql.Int,
  decimal: sql.Decimal(18, 4),
  date: sql.Date,
  datetime: sql.DateTime2,
  bit: sql.Bit,
};

function kindOf(p) {
  switch (p.ControlType) {
    case 'checkbox': return 'bit';
    case 'multiselect': return 'csv';
    case 'number': return p.DataType === 'int' ? 'int' : 'decimal';
    case 'date': return 'date';
    case 'datetime': return 'datetime';
    default: return TYPES[p.DataType] ? p.DataType : 'string'; // text, radio, dropdown
  }
}

const isEmpty = (v) => v === undefined || v === null || v === '' || (Array.isArray(v) && v.length === 0);
const truthy = (v) => v === true || v === 1 || v === '1' || String(v).toLowerCase() === 'true';

function coerce(kind, raw) {
  const type = TYPES[kind];
  if (kind === 'bit') return { type, value: truthy(raw) };
  if (isEmpty(raw)) return { type, value: null };
  switch (kind) {
    case 'int': {
      const n = Number(raw);
      if (!Number.isInteger(n)) throw new Error('bad int');
      return { type, value: n };
    }
    case 'decimal': {
      const n = Number(raw);
      if (!Number.isFinite(n)) throw new Error('bad number');
      return { type, value: n };
    }
    case 'date': {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(String(raw))) throw new Error('bad date');
      return { type, value: new Date(`${raw}T00:00:00Z`) };
    }
    case 'datetime': {
      const s = String(raw);
      const d = new Date(/[zZ]|[+-]\d{2}:?\d{2}$/.test(s) ? s : `${s}Z`);
      if (isNaN(d)) throw new Error('bad datetime');
      return { type, value: d };
    }
    case 'csv': {
      const list = Array.isArray(raw) ? raw : String(raw).split(',');
      return { type, value: list.map((x) => String(x).trim()).filter(Boolean).join(',') || null };
    }
    default:
      return { type, value: String(raw).slice(0, 4000) };
  }
}

function buildInputs(params, values = {}, strict = true) {
  const inputs = [];
  const errors = [];
  for (const p of params) {
    const slots = p.ControlType === 'daterange'
      ? [[`${p.ParamName}From`, 'date'], [`${p.ParamName}To`, 'date']]
      : [[p.ParamName, kindOf(p)]];
    for (const [name, kind] of slots) {
      const raw = values[name];
      try {
        inputs.push({ name, ...coerce(kind, raw) });
        if (strict && p.IsRequired && (kind === 'bit' ? !truthy(raw) : isEmpty(raw))) {
          errors.push(`${p.Label} is required`);
        }
      } catch {
        if (strict) errors.push(`${p.Label} has an invalid value`);
        else inputs.push({ name, type: TYPES[kind], value: null });
      }
    }
  }
  if (errors.length) throw new HttpError(400, [...new Set(errors)].join('. '));
  return inputs;
}

/* ------------------------------------------------------------------ */
/* Dropdown / multiselect / radio options                              */
/* ------------------------------------------------------------------ */
async function getOptions(report, paramName, values = {}) {
  const def = await getDefinition(report.ReportId);
  const p = def.params.find((x) => x.ParamName === paramName);
  if (!p) throw new HttpError(404, 'Unknown parameter');
  if (!p.OptionsQuery) return safeJson(p.OptionsJson) || [];

  // Options queries may reference only the parameters listed in DependsOn.
  const deps = splitList(p.DependsOn);
  const scoped = {};
  deps.forEach((d) => {
    ['', 'From', 'To'].forEach((s) => { if (values[d + s] !== undefined) scoped[d + s] = values[d + s]; });
  });
  const depParams = def.params.filter((x) => deps.includes(x.ParamName));
  const key = `opt:${p.ParamId}:${JSON.stringify(scoped)}`;

  return optCache.wrap(key, async () => {
    const request = (await getPool()).request();
    buildInputs(depParams, scoped, false).forEach((i) => request.input(i.name, i.type, i.value));
    const rs = (await request.query(p.OptionsQuery)).recordset;
    return rs.slice(0, 5000).map((row) => {
      const keys = Object.keys(row);
      const value = row.Value ?? row.value ?? row[keys[0]];
      const label = row.Label ?? row.label ?? row[keys[1]] ?? value;
      return { value, label: String(label) };
    });
  });
}

/* ------------------------------------------------------------------ */
/* Running a report                                                    */
/* ------------------------------------------------------------------ */
const NUM_DECL = new Set(['int', 'bigint', 'smallint', 'tinyint', 'decimal', 'numeric', 'float', 'real']);
const MONEY_DECL = new Set(['money', 'smallmoney']);
const DATETIME_DECL = new Set(['datetime', 'datetime2', 'smalldatetime', 'datetimeoffset']);
const NUMERIC_TYPES = new Set(['number', 'currency', 'percent']);
const VALID_TYPES = new Set(['text', 'number', 'currency', 'percent', 'date', 'datetime', 'bool']);

function inferType(meta, sample) {
  const decl = String((meta.type && (meta.type.declaration || meta.type.name)) || '').toLowerCase();
  if (NUM_DECL.has(decl)) return 'number';
  if (MONEY_DECL.has(decl)) return 'currency';
  if (decl === 'date') return 'date';
  if (DATETIME_DECL.has(decl)) return 'datetime';
  if (decl === 'bit') return 'bool';
  if (typeof sample === 'number') return 'number';
  if (typeof sample === 'boolean') return 'bool';
  return 'text';
}

const prettify = (s) =>
  String(s).replace(/_/g, ' ').replace(/([a-z])([A-Z])/g, '$1 $2').replace(/\bId\b/g, 'ID').trim();

async function runReport(report, values, user) {
  const def = await getDefinition(report.ReportId);
  const inputs = buildInputs(def.params, values, true);
  const started = Date.now();
  let rowCount = 0;
  let status = 'OK';

  try {
    const request = (await getPool()).request();
    request.arrayRowMode = true; // rows come back as arrays: smaller JSON, faster serialisation
    inputs.forEach((i) => request.input(i.name, i.type, i.value));

    const result = await request.query(report.QueryText);
    const rs = (result.recordsets && result.recordsets[0]) || result.recordset || [];
    let rows = rs;
    let truncated = false;
    if (rows.length > cfg.maxRows) {
      rows = rows.slice(0, cfg.maxRows);
      truncated = true;
    }
    rowCount = rows.length;

    const meta = Object.values(rs.columns || {}).sort((a, b) => a.index - b.index);
    const cfgMap = new Map(def.columns.map((c) => [c.ColumnName.toLowerCase(), c]));

    const columns = meta.map((m, i) => {
      const c = cfgMap.get(String(m.name).toLowerCase());
      const sample = rows.find((r) => r[i] !== null && r[i] !== undefined)?.[i];
      const type = c && VALID_TYPES.has(c.DataType) ? c.DataType : inferType(m, sample);
      return {
        i,
        key: m.name,
        label: c?.DisplayName || prettify(m.name),
        type,
        align: c?.Align || (NUMERIC_TYPES.has(type) ? 'right' : type === 'bool' ? 'center' : 'left'),
        width: c?.Width || null,
        visible: c ? !!c.IsVisible : true,
        summable: !!c?.IsSummable,
        _order: c ? c.SortOrder : 1e6 + i,
      };
    });
    columns.sort((a, b) => a._order - b._order || a.i - b.i);
    columns.forEach((c) => delete c._order);

    return { columns, rows, rowCount, truncated, maxRows: cfg.maxRows, durationMs: Date.now() - started };
  } catch (e) {
    status = 'ERROR';
    throw e;
  } finally {
    logRun(user.userId, report.ReportId, values, rowCount, Date.now() - started, status);
  }
}

/** Fire-and-forget audit trail. */
function logRun(userId, reportId, values, rowCount, durationMs, status) {
  getPool()
    .then((pool) =>
      pool.request()
        .input('u', sql.Int, userId)
        .input('r', sql.Int, reportId)
        .input('p', sql.NVarChar(sql.MAX), JSON.stringify(values || {}).slice(0, 8000))
        .input('n', sql.Int, rowCount)
        .input('d', sql.Int, durationMs)
        .input('s', sql.NVarChar(20), status)
        .query(`INSERT dbo.ReportRunLog (UserId, ReportId, ParamsJson, [RowCount], DurationMs, Status)
                VALUES (@u, @r, @p, @n, @d, @s)`)
    )
    .catch((e) => console.error('audit log failed:', e.message));
}

module.exports = { listReportsForRole, getReportForRole, getMeta, getOptions, runReport };
