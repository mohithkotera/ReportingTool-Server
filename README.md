# Report Studio - Server (Node.js + Express + SQL Server)

Every report, filter, dropdown list and column format lives in the database. The API only reads those definitions and runs them with typed, bound parameters.

## Run it
1. In SSMS open and run `sql/schema.sql`. It creates `ReportingDB`, the tables, 10,000 sample orders, 2,000 employees, 3 reports, 3 roles and 3 users.
2. `cp .env.example .env` and fill in `DB_SERVER`, `DB_USER`, `DB_PASSWORD` (SQL Server authentication must be enabled; TCP/IP enabled in SQL Server Configuration Manager). For `localhost\SQLEXPRESS` set `DB_INSTANCE=SQLEXPRESS` and clear `DB_PORT`.
3. `npm install && npm run dev` (Node 18+). Check `http://localhost:5000/api/health`.

Logins: `admin / Admin@123`, `manager / Manager@123`, `hr / Hr@123`.

## Tables
| Table | Purpose |
|---|---|
| Roles, Users | Login. `PasswordHash` = lower-case MD5 hex, e.g. `LOWER(CONVERT(VARCHAR(32), HASHBYTES('MD5','pwd'),2))` |
| Reports | Name, category, icon, `QueryText` (SQL with `@Param` placeholders) |
| RoleReports | Which role may see which report. No row, no access (enforced on every API call) |
| ReportParameters | One row per filter control |
| ReportColumns | Optional label, type, default visibility, totals per output column |
| ReportRunLog | Audit trail: who ran what, rows, milliseconds |

## Filter types (`ReportParameters.ControlType`)
`text`, `number`, `checkbox`, `radio`, `dropdown`, `multiselect`, `date`, `datetime`, `daterange`

- **Dropdown / multiselect values** come from `OptionsQuery`, a SELECT returning `Value` and `Label`. Radios use `OptionsJson` (`[{"value":"1","label":"Active"}]`).
- **Cascading dropdowns**: set `DependsOn='Category'` and reference `@Category` in the child's `OptionsQuery`.
- **daterange** creates `@<Name>From` and `@<Name>To`.
- **multiselect** arrives as a comma list: `col IN (SELECT value FROM STRING_SPLIT(@Region, N','))`.
- **Optional filter pattern**: `(@Status IS NULL OR Status = @Status)`. Unset filters arrive as NULL. Checkboxes arrive as 0/1.
- **Defaults**: literal, or `@today`, `@monthStart`, `@yearStart`, `@daysAgo:30`; for date ranges `from|to`, e.g. `@daysAgo:30|@today`.

## Add a report (no code change, no restart beyond ~60s cache)
```sql
INSERT dbo.Reports (ReportName, Category, Icon, QueryText)
VALUES ('Open Orders', 'Sales', 'table',
 N'SELECT OrderId, OrderDate, CustomerName, TotalAmount FROM dbo.SalesOrders
   WHERE Status = N''Pending'' AND (@Region IS NULL OR Region = @Region)');
DECLARE @id INT = SCOPE_IDENTITY();
INSERT dbo.ReportParameters (ReportId, ParamName, Label, ControlType, OptionsQuery, SortOrder)
VALUES (@id, 'Region', 'Region', 'dropdown', N'SELECT DISTINCT Region AS Value, Region AS Label FROM dbo.SalesOrders', 10);
INSERT dbo.RoleReports SELECT RoleId, @id FROM dbo.Roles WHERE RoleName IN ('Admin','Manager');
```

## Speed
- Rows are sent as arrays (no repeated column names) and gzip-compressed; 10k rows is roughly 150-300 KB on the wire.
- Shared connection pool, cached report definitions and dropdown lists (60 s), indexed sample tables.
- `MAX_ROWS` (default 100,000) caps a single result.
- For your own large reports, index the columns used in the WHERE clause.

## Security notes
- All filter values are bound parameters; the SQL stored in `Reports` is only editable by whoever has DB write access.
- JWT in the `Authorization` header; the user's active flag and role are re-checked against the DB (cached 30 s), so disabling a user or changing a role takes effect quickly.
- **MD5 is a broken password hash** (fast to brute-force). It is used here because it was required. Swapping to bcrypt/argon2 later only touches `src/utils/crypto.js` and the login route. Set a strong `JWT_SECRET` and serve over HTTPS in production.
