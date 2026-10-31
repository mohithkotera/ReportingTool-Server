/* =====================================================================
   Report Studio - SQL Server schema + sample data
   Run in SSMS (connect as a login that can create databases).
   Seed logins:  admin / Admin@123   manager / Manager@123   hr / Hr@123
   ===================================================================== */
IF DB_ID('ReportingDB') IS NULL CREATE DATABASE ReportingDB;
GO
USE ReportingDB;
GO

/* ------------------------- security ------------------------- */
IF OBJECT_ID('dbo.Roles') IS NULL
CREATE TABLE dbo.Roles (
  RoleId      INT IDENTITY(1,1) PRIMARY KEY,
  RoleName    NVARCHAR(50)  NOT NULL UNIQUE,
  Description NVARCHAR(200) NULL
);

IF OBJECT_ID('dbo.Users') IS NULL
CREATE TABLE dbo.Users (
  UserId       INT IDENTITY(1,1) PRIMARY KEY,
  Username     NVARCHAR(60)  NOT NULL UNIQUE,
  FullName     NVARCHAR(120) NOT NULL,
  Email        NVARCHAR(160) NULL,
  PasswordHash CHAR(32)      NOT NULL,           -- lower-case MD5 hex
  RoleId       INT           NOT NULL REFERENCES dbo.Roles(RoleId),
  IsActive     BIT           NOT NULL DEFAULT 1,
  LastLoginAt  DATETIME2     NULL,
  CreatedAt    DATETIME2     NOT NULL DEFAULT SYSUTCDATETIME()
);

/* ------------------------- report catalogue ------------------------- */
IF OBJECT_ID('dbo.Reports') IS NULL
CREATE TABLE dbo.Reports (
  ReportId    INT IDENTITY(1,1) PRIMARY KEY,
  ReportName  NVARCHAR(150) NOT NULL,
  Description NVARCHAR(400) NULL,
  Category    NVARCHAR(80)  NOT NULL DEFAULT 'General',
  Icon        NVARCHAR(40)  NULL,                 -- chart | table | users | wallet | trending | file
  QueryText   NVARCHAR(MAX) NOT NULL,             -- uses @ParamName placeholders (bound, never concatenated)
  SortOrder   INT NOT NULL DEFAULT 100,
  IsActive    BIT NOT NULL DEFAULT 1
);

IF OBJECT_ID('dbo.RoleReports') IS NULL
CREATE TABLE dbo.RoleReports (
  RoleId   INT NOT NULL REFERENCES dbo.Roles(RoleId),
  ReportId INT NOT NULL REFERENCES dbo.Reports(ReportId),
  PRIMARY KEY (RoleId, ReportId)
);

/* ControlType: text | number | checkbox | radio | dropdown | multiselect | date | datetime | daterange
   DataType   : string | int | decimal | bit   (how dropdown/radio values are typed when bound)
   daterange  : creates two SQL parameters  @<ParamName>From and @<ParamName>To
   multiselect: bound as comma separated string  ->  IN (SELECT value FROM STRING_SPLIT(@P, ','))
   OptionsQuery: SELECT Value, Label ...  (may reference parameters listed in DependsOn)
   OptionsJson : static options  [{"value":"1","label":"One"}]
   DefaultValue: literal, or tokens @today @monthStart @yearStart @daysAgo:30 (daterange: 'from|to') */
IF OBJECT_ID('dbo.ReportParameters') IS NULL
CREATE TABLE dbo.ReportParameters (
  ParamId      INT IDENTITY(1,1) PRIMARY KEY,
  ReportId     INT NOT NULL REFERENCES dbo.Reports(ReportId),
  ParamName    NVARCHAR(60)  NOT NULL,
  Label        NVARCHAR(100) NOT NULL,
  ControlType  NVARCHAR(20)  NOT NULL
    CHECK (ControlType IN ('text','number','checkbox','radio','dropdown','multiselect','date','datetime','daterange')),
  DataType     NVARCHAR(20)  NOT NULL DEFAULT 'string',
  IsRequired   BIT NOT NULL DEFAULT 0,
  DefaultValue NVARCHAR(500) NULL,
  Placeholder  NVARCHAR(120) NULL,
  OptionsQuery NVARCHAR(MAX) NULL,
  OptionsJson  NVARCHAR(MAX) NULL,
  DependsOn    NVARCHAR(200) NULL,                -- comma separated parent ParamNames (cascading)
  ColSpan      TINYINT NOT NULL DEFAULT 1,        -- 1..4 grid columns
  SortOrder    INT NOT NULL DEFAULT 100,
  CONSTRAINT UQ_ReportParameters UNIQUE (ReportId, ParamName)
);

/* Optional per-column presentation. Columns not listed are still shown (auto-detected).
   DataType: text | number | currency | percent | date | datetime | bool */
IF OBJECT_ID('dbo.ReportColumns') IS NULL
CREATE TABLE dbo.ReportColumns (
  ColId       INT IDENTITY(1,1) PRIMARY KEY,
  ReportId    INT NOT NULL REFERENCES dbo.Reports(ReportId),
  ColumnName  NVARCHAR(128) NOT NULL,
  DisplayName NVARCHAR(128) NULL,
  DataType    NVARCHAR(20)  NULL,
  Align       NVARCHAR(10)  NULL,
  Width       INT NULL,
  IsVisible   BIT NOT NULL DEFAULT 1,             -- hidden by default but selectable in the column picker
  IsSummable  BIT NOT NULL DEFAULT 0,             -- adds a total in the grid footer and exports
  SortOrder   INT NOT NULL DEFAULT 100,
  CONSTRAINT UQ_ReportColumns UNIQUE (ReportId, ColumnName)
);

IF OBJECT_ID('dbo.ReportRunLog') IS NULL
CREATE TABLE dbo.ReportRunLog (
  LogId      BIGINT IDENTITY(1,1) PRIMARY KEY,
  UserId     INT NOT NULL,
  ReportId   INT NOT NULL,
  ParamsJson NVARCHAR(MAX) NULL,
  [RowCount] INT NULL,
  DurationMs INT NULL,
  Status     NVARCHAR(20) NULL,
  RunAt      DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

/* ------------------------- sample data tables ------------------------- */
IF OBJECT_ID('dbo.SalesOrders') IS NULL
CREATE TABLE dbo.SalesOrders (
  OrderId      INT IDENTITY(1001,1) PRIMARY KEY,
  OrderDate    DATE          NOT NULL,
  Region       NVARCHAR(30)  NOT NULL,
  Category     NVARCHAR(40)  NOT NULL,
  Product      NVARCHAR(60)  NOT NULL,
  CustomerName NVARCHAR(80)  NOT NULL,
  SalesRep     NVARCHAR(60)  NOT NULL,
  Status       NVARCHAR(20)  NOT NULL,
  Quantity     INT           NOT NULL,
  UnitPrice    DECIMAL(12,2) NOT NULL,
  Discount     DECIMAL(5,2)  NOT NULL,
  TotalAmount  DECIMAL(14,2) NOT NULL,
  IsPaid       BIT           NOT NULL
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_SalesOrders_OrderDate')
  CREATE INDEX IX_SalesOrders_OrderDate ON dbo.SalesOrders (OrderDate)
  INCLUDE (Region, Category, Product, Status, TotalAmount, IsPaid);

IF OBJECT_ID('dbo.Employees') IS NULL
CREATE TABLE dbo.Employees (
  EmployeeId  INT IDENTITY(5001,1) PRIMARY KEY,
  FullName    NVARCHAR(100) NOT NULL,
  Department  NVARCHAR(40)  NOT NULL,
  Designation NVARCHAR(60)  NOT NULL,
  City        NVARCHAR(40)  NOT NULL,
  JoinDate    DATE          NOT NULL,
  Salary      DECIMAL(12,2) NOT NULL,
  IsActive    BIT           NOT NULL
);
GO

/* ------------------------- seed: roles, users ------------------------- */
IF NOT EXISTS (SELECT 1 FROM dbo.Roles)
BEGIN
  INSERT dbo.Roles (RoleName, Description) VALUES
    ('Admin',   'Full access to every report'),
    ('Manager', 'Sales reporting'),
    ('HR',      'People reporting');

  INSERT dbo.Users (Username, FullName, Email, PasswordHash, RoleId) VALUES
    ('admin',   'Aarav Sharma', 'aarav.sharma@example.com', LOWER(CONVERT(VARCHAR(32), HASHBYTES('MD5', 'Admin@123'),   2)), (SELECT RoleId FROM dbo.Roles WHERE RoleName='Admin')),
    ('manager', 'Priya Nair',   'priya.nair@example.com',   LOWER(CONVERT(VARCHAR(32), HASHBYTES('MD5', 'Manager@123'), 2)), (SELECT RoleId FROM dbo.Roles WHERE RoleName='Manager')),
    ('hr',      'Rohan Mehta',  'rohan.mehta@example.com',  LOWER(CONVERT(VARCHAR(32), HASHBYTES('MD5', 'Hr@123'),      2)), (SELECT RoleId FROM dbo.Roles WHERE RoleName='HR'));
END
GO

/* ------------------------- seed: 10,000 sales orders ------------------------- */
IF NOT EXISTS (SELECT 1 FROM dbo.SalesOrders)
BEGIN
  CREATE TABLE #P (Category NVARCHAR(40), Product NVARCHAR(60), Price DECIMAL(12,2));
  INSERT #P VALUES
    ('Electronics','Laptop 14"',54990),('Electronics','Wireless Earbuds',3499),('Electronics','Smart Monitor',18990),
    ('Furniture','Ergonomic Chair',12490),('Furniture','Standing Desk',27990),('Furniture','Bookshelf',6490),
    ('Office Supplies','Printer Paper (Box)',1290),('Office Supplies','Whiteboard',2190),('Office Supplies','Desk Organiser',790),
    ('Apparel','Team Jacket',2490),('Apparel','Polo Shirt',899),('Apparel','Safety Shoes',2990);
  CREATE TABLE #R (V NVARCHAR(60));  INSERT #R VALUES ('North'),('South'),('East'),('West'),('Central');
  CREATE TABLE #C (V NVARCHAR(80));  INSERT #C VALUES ('Tata Consultancy'),('Infosys Ltd'),('Reliance Retail'),('Mahindra Group'),('Wipro Technologies'),('HCL Systems'),('Godrej Interio'),('Asian Paints'),('Bajaj Auto'),('Larsen & Toubro'),('ITC Limited'),('Hindustan Unilever'),('Zomato Ltd'),('Flipkart Internet'),('Paytm Services'),('Dr. Reddys Labs');
  CREATE TABLE #S (V NVARCHAR(60));  INSERT #S VALUES ('Ankit Verma'),('Neha Kapoor'),('Sandeep Rao'),('Meera Iyer'),('Karan Singh'),('Divya Menon'),('Vikram Joshi'),('Pooja Das');

  ;WITH N AS (
    SELECT TOP (10000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
  )
  INSERT dbo.SalesOrders (OrderDate, Region, Category, Product, CustomerName, SalesRep, Status, Quantity, UnitPrice, Discount, TotalAmount, IsPaid)
  SELECT d.OrderDate, r.V, p.Category, p.Product, c.V, s.V, st.Status, q.Qty, p.Price, q.Disc,
         CAST(q.Qty * p.Price * (1 - q.Disc / 100.0) AS DECIMAL(14,2)),
         CASE WHEN st.Status IN ('Completed','Shipped') THEN 1 ELSE 0 END
  FROM N
  CROSS APPLY (SELECT DATEADD(DAY, -(ABS(CHECKSUM(NEWID(), N.n)) % 730), CAST(GETDATE() AS DATE)) AS OrderDate) d
  CROSS APPLY (SELECT TOP 1 V FROM #R ORDER BY CHECKSUM(NEWID(), N.n)) r
  CROSS APPLY (SELECT TOP 1 * FROM #P ORDER BY CHECKSUM(NEWID(), N.n)) p
  CROSS APPLY (SELECT TOP 1 V FROM #C ORDER BY CHECKSUM(NEWID(), N.n)) c
  CROSS APPLY (SELECT TOP 1 V FROM #S ORDER BY CHECKSUM(NEWID(), N.n)) s
  CROSS APPLY (SELECT ABS(CHECKSUM(NEWID(), N.n)) % 100 AS roll) x
  CROSS APPLY (SELECT CASE WHEN x.roll < 65 THEN 'Completed' WHEN x.roll < 82 THEN 'Shipped'
                           WHEN x.roll < 94 THEN 'Pending' ELSE 'Cancelled' END AS Status) st
  CROSS APPLY (SELECT (ABS(CHECKSUM(NEWID(), N.n)) % 10) + 1 AS Qty,
                      (ABS(CHECKSUM(NEWID(), N.n)) % 5) * 2.5 AS Disc) q;

  DROP TABLE #P, #R, #C, #S;
END
GO

/* ------------------------- seed: 2,000 employees ------------------------- */
IF NOT EXISTS (SELECT 1 FROM dbo.Employees)
BEGIN
  CREATE TABLE #F (V NVARCHAR(30)); INSERT #F VALUES ('Aditya'),('Ananya'),('Arjun'),('Bhavna'),('Chirag'),('Deepa'),('Farhan'),('Gauri'),('Harsh'),('Isha'),('Jatin'),('Kavya'),('Lakshmi'),('Manish'),('Nikita'),('Omkar'),('Pranav'),('Riya'),('Sahil'),('Tanvi');
  CREATE TABLE #L (V NVARCHAR(30)); INSERT #L VALUES ('Agarwal'),('Bose'),('Chopra'),('Desai'),('Etheridge'),('Fernandes'),('Gupta'),('Hegde'),('Iyer'),('Jain'),('Khanna'),('Lal'),('Malhotra'),('Naidu'),('Oberoi'),('Patel'),('Qureshi'),('Reddy'),('Saxena'),('Trivedi');
  CREATE TABLE #D (Dept NVARCHAR(40), Title NVARCHAR(60));
  INSERT #D VALUES ('Engineering','Software Engineer'),('Engineering','Senior Engineer'),('Engineering','QA Analyst'),('Finance','Accountant'),('Finance','Finance Manager'),
                   ('Sales','Account Executive'),('Sales','Sales Manager'),('HR','HR Executive'),('HR','Talent Partner'),('Operations','Operations Lead'),('Marketing','Content Strategist'),('Marketing','Brand Manager');
  CREATE TABLE #T (V NVARCHAR(40)); INSERT #T VALUES ('Delhi'),('Mumbai'),('Bengaluru'),('Hyderabad'),('Pune'),('Chennai');

  ;WITH N AS (SELECT TOP (2000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM sys.all_objects a CROSS JOIN sys.all_objects b)
  INSERT dbo.Employees (FullName, Department, Designation, City, JoinDate, Salary, IsActive)
  SELECT f.V + ' ' + l.V, d.Dept, d.Title, t.V,
         DATEADD(DAY, -(ABS(CHECKSUM(NEWID(), N.n)) % 2920), CAST(GETDATE() AS DATE)),
         CAST(300000 + (ABS(CHECKSUM(NEWID(), N.n)) % 2200000) AS DECIMAL(12,2)),
         CASE WHEN ABS(CHECKSUM(NEWID(), N.n)) % 100 < 90 THEN 1 ELSE 0 END
  FROM N
  CROSS APPLY (SELECT TOP 1 V FROM #F ORDER BY CHECKSUM(NEWID(), N.n)) f
  CROSS APPLY (SELECT TOP 1 V FROM #L ORDER BY CHECKSUM(NEWID(), N.n)) l
  CROSS APPLY (SELECT TOP 1 Dept, Title FROM #D ORDER BY CHECKSUM(NEWID(), N.n)) d
  CROSS APPLY (SELECT TOP 1 V FROM #T ORDER BY CHECKSUM(NEWID(), N.n)) t;

  DROP TABLE #F, #L, #D, #T;
END
GO

/* ------------------------- seed: report definitions ------------------------- */
IF NOT EXISTS (SELECT 1 FROM dbo.Reports)
BEGIN
  DECLARE @sales INT, @summary INT, @emp INT;

  /* ===== 1. Sales Register ===== */
  INSERT dbo.Reports (ReportName, Description, Category, Icon, SortOrder, QueryText) VALUES (
    'Sales Register', 'Order-level sales with region, product and payment filters.', 'Sales', 'chart', 10,
N'SELECT OrderId, OrderDate, Region, Category, Product, CustomerName, SalesRep, Status,
       Quantity, UnitPrice, Discount, TotalAmount, IsPaid
FROM dbo.SalesOrders
WHERE (@OrderDateFrom IS NULL OR OrderDate >= @OrderDateFrom)
  AND (@OrderDateTo   IS NULL OR OrderDate <= @OrderDateTo)
  AND (@Region   IS NULL OR Region IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Region, N'','')))
  AND (@Category IS NULL OR Category = @Category)
  AND (@Product  IS NULL OR Product  = @Product)
  AND (@Status   IS NULL OR Status   = @Status)
  AND (@MinAmount IS NULL OR TotalAmount >= @MinAmount)
  AND (@Customer IS NULL OR CHARINDEX(@Customer, CustomerName) > 0)
  AND (@PaidOnly = 0 OR IsPaid = 1)
ORDER BY OrderDate DESC, OrderId DESC');
  SET @sales = SCOPE_IDENTITY();

  INSERT dbo.ReportParameters (ReportId, ParamName, Label, ControlType, DataType, IsRequired, DefaultValue, Placeholder, OptionsQuery, OptionsJson, DependsOn, ColSpan, SortOrder) VALUES
   (@sales,'OrderDate','Order date','daterange','string',0,'@daysAgo:365|@today',NULL,NULL,NULL,NULL,2,10),
   (@sales,'Region','Region','multiselect','string',0,NULL,'All regions',
      N'SELECT DISTINCT Region AS Value, Region AS Label FROM dbo.SalesOrders ORDER BY 1',NULL,NULL,1,20),
   (@sales,'Category','Category','dropdown','string',0,NULL,'All categories',
      N'SELECT DISTINCT Category AS Value, Category AS Label FROM dbo.SalesOrders ORDER BY 1',NULL,NULL,1,30),
   (@sales,'Product','Product','dropdown','string',0,NULL,'All products',
      N'SELECT DISTINCT Product AS Value, Product AS Label FROM dbo.SalesOrders WHERE (@Category IS NULL OR Category = @Category) ORDER BY 1',NULL,'Category',1,40),
   (@sales,'Status','Order status','radio','string',0,'',NULL,NULL,
      N'[{"value":"","label":"All"},{"value":"Completed","label":"Completed"},{"value":"Shipped","label":"Shipped"},{"value":"Pending","label":"Pending"},{"value":"Cancelled","label":"Cancelled"}]',NULL,2,50),
   (@sales,'Customer','Customer contains','text','string',0,NULL,'Type part of a name',NULL,NULL,NULL,1,60),
   (@sales,'MinAmount','Minimum amount','number','decimal',0,NULL,'0.00',NULL,NULL,NULL,1,70),
   (@sales,'PaidOnly','Paid orders only','checkbox','string',0,NULL,NULL,NULL,NULL,NULL,1,80);

  INSERT dbo.ReportColumns (ReportId, ColumnName, DisplayName, DataType, IsVisible, IsSummable, SortOrder) VALUES
   (@sales,'OrderId','Order no.','text',1,0,10),
   (@sales,'OrderDate','Order date','date',1,0,20),
   (@sales,'Region','Region','text',1,0,30),
   (@sales,'Category','Category','text',1,0,40),
   (@sales,'Product','Product','text',1,0,50),
   (@sales,'CustomerName','Customer','text',1,0,60),
   (@sales,'SalesRep','Sales rep','text',0,0,70),
   (@sales,'Status','Status','text',1,0,80),
   (@sales,'Quantity','Qty','number',1,1,90),
   (@sales,'UnitPrice','Unit price','currency',0,0,100),
   (@sales,'Discount','Discount %','number',0,0,110),
   (@sales,'TotalAmount','Total amount','currency',1,1,120),
   (@sales,'IsPaid','Paid','bool',1,0,130);

  /* ===== 2. Monthly Sales Summary (aggregated) ===== */
  INSERT dbo.Reports (ReportName, Description, Category, Icon, SortOrder, QueryText) VALUES (
    'Monthly Sales Summary', 'Revenue, orders and average order value by month and region.', 'Sales', 'trending', 20,
N'SELECT YEAR(OrderDate) AS [Year], DATENAME(MONTH, OrderDate) AS [Month], MONTH(OrderDate) AS MonthNo, Region,
       COUNT(*) AS Orders, SUM(Quantity) AS Units,
       SUM(TotalAmount) AS Revenue, AVG(TotalAmount) AS AvgOrderValue,
       SUM(CASE WHEN IsPaid = 1 THEN TotalAmount ELSE 0 END) AS PaidRevenue
FROM dbo.SalesOrders
WHERE (@Year IS NULL OR YEAR(OrderDate) = @Year)
  AND (@Region IS NULL OR Region IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Region, N'','')))
  AND (@Category IS NULL OR Category = @Category)
GROUP BY YEAR(OrderDate), DATENAME(MONTH, OrderDate), MONTH(OrderDate), Region
ORDER BY YEAR(OrderDate) DESC, MONTH(OrderDate) DESC, Region');
  SET @summary = SCOPE_IDENTITY();

  INSERT dbo.ReportParameters (ReportId, ParamName, Label, ControlType, DataType, IsRequired, Placeholder, OptionsQuery, SortOrder) VALUES
   (@summary,'Year','Year','dropdown','int',0,'All years',N'SELECT DISTINCT YEAR(OrderDate) AS Value, CAST(YEAR(OrderDate) AS NVARCHAR(4)) AS Label FROM dbo.SalesOrders ORDER BY 1 DESC',10),
   (@summary,'Region','Region','multiselect','string',0,'All regions',N'SELECT DISTINCT Region AS Value, Region AS Label FROM dbo.SalesOrders ORDER BY 1',20),
   (@summary,'Category','Category','dropdown','string',0,'All categories',N'SELECT DISTINCT Category AS Value, Category AS Label FROM dbo.SalesOrders ORDER BY 1',30);

  INSERT dbo.ReportColumns (ReportId, ColumnName, DisplayName, DataType, IsVisible, IsSummable, SortOrder) VALUES
   (@summary,'Year','Year','text',1,0,10),
   (@summary,'Month','Month','text',1,0,20),
   (@summary,'MonthNo','Month no.','text',0,0,25),
   (@summary,'Region','Region','text',1,0,30),
   (@summary,'Orders','Orders','number',1,1,40),
   (@summary,'Units','Units','number',1,1,50),
   (@summary,'Revenue','Revenue','currency',1,1,60),
   (@summary,'AvgOrderValue','Avg. order value','currency',1,0,70),
   (@summary,'PaidRevenue','Paid revenue','currency',1,1,80);

  /* ===== 3. Employee Directory ===== */
  INSERT dbo.Reports (ReportName, Description, Category, Icon, SortOrder, QueryText) VALUES (
    'Employee Directory', 'Headcount, joining dates and salary bands across departments.', 'People', 'users', 10,
N'SELECT EmployeeId, FullName, Department, Designation, City, JoinDate, Salary, IsActive
FROM dbo.Employees
WHERE (@JoinDateFrom IS NULL OR JoinDate >= @JoinDateFrom)
  AND (@JoinDateTo   IS NULL OR JoinDate <= @JoinDateTo)
  AND (@Department IS NULL OR Department IN (SELECT LTRIM(RTRIM(value)) FROM STRING_SPLIT(@Department, N'','')))
  AND (@City IS NULL OR City = @City)
  AND (@Active IS NULL OR IsActive = @Active)
  AND (@MinSalary IS NULL OR Salary >= @MinSalary)
  AND (@Name IS NULL OR CHARINDEX(@Name, FullName) > 0)
ORDER BY FullName');
  SET @emp = SCOPE_IDENTITY();

  INSERT dbo.ReportParameters (ReportId, ParamName, Label, ControlType, DataType, IsRequired, Placeholder, OptionsQuery, OptionsJson, ColSpan, SortOrder) VALUES
   (@emp,'Department','Department','multiselect','string',0,'All departments',N'SELECT DISTINCT Department AS Value, Department AS Label FROM dbo.Employees ORDER BY 1',NULL,1,10),
   (@emp,'City','City','dropdown','string',0,'All cities',N'SELECT DISTINCT City AS Value, City AS Label FROM dbo.Employees ORDER BY 1',NULL,1,20),
   (@emp,'JoinDate','Joining date','daterange','string',0,NULL,NULL,NULL,2,30),
   (@emp,'Active','Employment','radio','int',0,NULL,NULL,N'[{"value":"","label":"All"},{"value":"1","label":"Active"},{"value":"0","label":"Left"}]',1,40),
   (@emp,'MinSalary','Minimum salary','number','decimal',0,'0',NULL,NULL,1,50),
   (@emp,'Name','Name contains','text','string',0,'Search by name',NULL,NULL,1,60);

  INSERT dbo.ReportColumns (ReportId, ColumnName, DisplayName, DataType, IsVisible, IsSummable, SortOrder) VALUES
   (@emp,'EmployeeId','Emp. no.','text',1,0,10),
   (@emp,'FullName','Name','text',1,0,20),
   (@emp,'Department','Department','text',1,0,30),
   (@emp,'Designation','Designation','text',1,0,40),
   (@emp,'City','City','text',1,0,50),
   (@emp,'JoinDate','Joined','date',1,0,60),
   (@emp,'Salary','Annual salary','currency',1,1,70),
   (@emp,'IsActive','Active','bool',1,0,80);

  /* ===== role -> report assignment ===== */
  INSERT dbo.RoleReports (RoleId, ReportId)
  SELECT r.RoleId, x.ReportId FROM dbo.Roles r CROSS JOIN dbo.Reports x WHERE r.RoleName = 'Admin';
  INSERT dbo.RoleReports (RoleId, ReportId)
  SELECT r.RoleId, x.ReportId FROM dbo.Roles r JOIN dbo.Reports x ON x.Category = 'Sales' WHERE r.RoleName = 'Manager';
  INSERT dbo.RoleReports (RoleId, ReportId)
  SELECT r.RoleId, x.ReportId FROM dbo.Roles r JOIN dbo.Reports x ON x.Category = 'People' WHERE r.RoleName = 'HR';
END
GO

SELECT 'Sales rows' AS Item, COUNT(*) AS Total FROM dbo.SalesOrders
UNION ALL SELECT 'Employees', COUNT(*) FROM dbo.Employees
UNION ALL SELECT 'Reports', COUNT(*) FROM dbo.Reports;
GO
