# Oracle RDS → PostgreSQL RDS Migration Guide
### AWS DMS CDC Setup, Schema Conversion & Post-Migration Patterns

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Oracle RDS Source Preparation](#2-oracle-rds-source-preparation)
3. [Supplemental Logging Setup](#3-supplemental-logging-setup)
4. [AWS DMS Task Configuration](#4-aws-dms-task-configuration)
5. [Schema Conversion (SCT) Patterns](#5-schema-conversion-sct-patterns)
6. [Data Type Mapping Reference](#6-data-type-mapping-reference)
7. [PL/SQL → PL/pgSQL Conversion Patterns](#7-plsql--plpgsql-conversion-patterns)
8. [Known Issues & Solutions](#8-known-issues--solutions)
9. [Post-Migration Validation](#9-post-migration-validation)
10. [CDC Readiness Checklist](#10-cdc-readiness-checklist)

---

## 1. Architecture Overview

```
Oracle RDS (Source)          AWS DMS                  PostgreSQL RDS (Target)
┌─────────────────┐    ┌──────────────────┐    ┌──────────────────────────┐
│  HR Schema      │───▶│  Full Load Task  │───▶│  hr schema (pg18)        │
│  ARCHIVELOG ON  │    │  + CDC Task      │    │  db.t3.small / 2GB RAM   │
│  Supp. Logging  │    │  Replication     │    │  gp3 / 20 GiB            │
│  enabled        │    │  Instance        │    │  Parameter Group: pg18   │
└─────────────────┘    └──────────────────┘    └──────────────────────────┘
```

**Key constraints on both sides:**
- Oracle RDS users are **not SYSDBA** — use `rdsadmin.rdsadmin_util` package for privileged operations
- PostgreSQL RDS does **not honour** `session_replication_role` set in parameter groups — must be set per-session or via DMS hooks
- Performance Insights and Enhanced Monitoring should be enabled on the target during migration

---

## 2. Oracle RDS Source Preparation

### 2.1 Connect to Oracle RDS

```sql
sqlplus admin/password@(DESCRIPTION=
  (ADDRESS_LIST=(ADDRESS=(PROTOCOL=TCP)
    (HOST=<rds-endpoint>)(PORT=1521)))
  (CONNECT_DATA=(SID=ORCL)))
```

### 2.2 Verify Archive Log Mode

```sql
SELECT log_mode FROM v$database;
-- Expected: ARCHIVELOG
```

> **Note:** `ARCHIVE LOG LIST` fails on RDS with `ORA-01031`. RDS Oracle runs in ARCHIVELOG mode by default — no action needed.

> **Non-RDS Oracle only** (on-prem / EC2): If not in ARCHIVELOG mode, enable it manually:
> ```sql
> ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
> SHUTDOWN IMMEDIATE;
> STARTUP MOUNT;
> ALTER DATABASE ARCHIVELOG;
> ALTER DATABASE OPEN;
> ```

### 2.3 Grant Required Privileges

```sql
-- Grant DBA to schema owner for migration activities
GRANT DBA TO hr;

-- Connect as HR for table-level operations
CONN hr
```

### 2.4 Force Redo Log Switch (RDS Method)

Must be executed as **ADMIN** user:

```sql
EXEC rdsadmin.rdsadmin_util.switch_logfile;
-- Expected: PL/SQL procedure successfully completed.
```

> **HR user receives:** `PLS-00201: identifier 'RDSADMIN.RDSADMIN_UTIL' must be declared`
> Always run `rdsadmin` procedures as ADMIN, not as the schema owner.

---

## 3. Supplemental Logging Setup

Supplemental logging is required for CDC (Change Data Capture) to work correctly. DMS needs enough redo data to reconstruct UPDATE and DELETE statements.

### 3.1 Enable Minimum Supplemental Logging (RDS Method)

```sql
-- Direct command FAILS on RDS:
ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;
-- Error: ORA-01031: insufficient privileges

-- Correct RDS method:
EXEC rdsadmin.rdsadmin_util.alter_supplemental_logging('ADD');
-- Expected: PL/SQL procedure successfully completed.
```

### 3.2 Verify Supplemental Logging

```sql
-- Quick check
SELECT supplemental_log_data_min FROM v$database;
-- Expected: YES

-- Detailed check
SELECT
    supplemental_log_data_min,
    supplemental_log_data_pk,
    supplemental_log_data_ui,
    supplemental_log_data_fk,
    supplemental_log_data_all
FROM v$database;
```

**Expected baseline state after minimum logging:**

| Column | Value |
|--------|-------|
| MIN    | YES   |
| PK     | NO    |
| UI     | NO    |
| FK     | NO    |
| ALL    | NO    |

### 3.3 Enable Table-Level Supplemental Logging

Minimum supplemental logging alone is insufficient for DMS CDC. Each replicated table needs `ALL COLUMNS` supplemental logging.

**Generate statements dynamically:**
```sql
SELECT
    'ALTER TABLE ' || table_name ||
    ' ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;'
FROM all_tables
WHERE owner = 'HR';
```

**Run as HR schema owner** (ADMIN will get `ORA-00942`):
```sql
ALTER TABLE REGIONS          ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE COUNTRIES        ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE LOCATIONS        ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE DEPARTMENTS      ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE JOBS             ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE EMPLOYEES        ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE JOB_HISTORY      ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE IDENTITY_TST     ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE SYSTEM_EVENTS    ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE CLOB_DATA_TABLE  ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE BLOB_DATA_TABLE  ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE RANDOM_DATA_TABLE ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE SALES            ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
ALTER TABLE SAMPLE_TABLE     ADD SUPPLEMENTAL LOG DATA (ALL) COLUMNS;
```

### 3.4 Add Primary Keys to Tables Missing One

DMS CDC requires a primary key for reliable row identification:
```sql
ALTER TABLE BLOB_DATA_TABLE
ADD CONSTRAINT id_key PRIMARY KEY (id);
```

### 3.5 Generate Redo for CDC Testing

```sql
UPDATE jobs
SET max_salary = 100000
WHERE job_id = 'AD_PRES';

COMMIT;

-- Force log switch after testing
EXEC rdsadmin.rdsadmin_util.switch_logfile;
```

---

## 4. AWS DMS Task Configuration

### 4.1 Task Settings — Recommended vs Observed

| Setting | Observed | Recommended | Reason |
|---------|----------|-------------|--------|
| Target table prep mode | Truncate | **Drop tables on target** | Truncate + FK constraints causes cascade failures |
| LOB column mode | Limited (32 KB) | Full LOB (if BLOBs/CLOBs > 32 KB) | Limited mode silently truncates large objects |
| Data validation | Off | **Validation with data migration** | Catches row-count mismatches post-load |
| CloudWatch Logs | Off | **On** | Essential for diagnosing DMS-side errors |
| Performance Insights | Disabled | **Enable** | Reveals blocking sessions on target |

### 4.2 The FK + Truncate Problem

**Symptom:** DMS issues individual `TRUNCATE TABLE` statements per table in parallel, ignoring FK dependency order:

```
ERROR: cannot truncate a table referenced in a foreign key constraint
DETAIL: Table "locations" references "countries".
HINT: Truncate table "locations" at the same time, or use TRUNCATE ... CASCADE.
STATEMENT: TRUNCATE TABLE "hr"."countries"
```

**HR schema FK dependency graph:**
```
regions → countries → locations → departments ⇄ employees → jobs
                                       ↑
                                  job_history
```

**Fix Option 1 — Switch to "Drop tables on target"** *(recommended)*
DMS drops and recreates tables, bypassing FK constraints entirely during load.

**Fix Option 2 — Manual cascade truncate before the task:**
```sql
TRUNCATE hr.regions, hr.countries, hr.locations,
         hr.departments, hr.employees, hr.jobs, hr.job_history
CASCADE;
```

**Fix Option 3 — Disable triggers per table** (requires `rds_superuser`):
```sql
ALTER TABLE hr.locations DISABLE TRIGGER ALL;
-- ... all tables ...
-- Re-enable after DMS completes
ALTER TABLE hr.locations ENABLE TRIGGER ALL;
```

### 4.3 `session_replication_role` — RDS Limitation

Setting `session_replication_role = replica` in the **RDS parameter group** has **no effect**. AWS intentionally blocks this at the instance level.

```sql
-- Verify: even if pg18 parameter group shows "Modified", this will return:
SHOW session_replication_role;
-- Returns: origin    ← NOT replica
```

The workaround via parameter group does not work on RDS PostgreSQL. Use one of the Fix Options above instead.

---

## 5. Schema Conversion (SCT) Patterns

AWS SCT handles most conversion automatically but generates code that requires post-migration cleanup.

### 5.1 `DBMS_OUTPUT` — the `aws_oracle_ext` Bridge

SCT converts `DBMS_OUTPUT.PUT_LINE` to the extension-based equivalent:

```sql
-- SCT output (works, but requires manual retrieval):
CALL aws_oracle_ext.dbms_output$put_line(
    a => CONCAT_WS('', 'Employee ID: ', v_employee_id, ...));
```

To actually see output from this extension:
```sql
-- Step 1: Enable the buffer (equivalent to SET SERVEROUTPUT ON)
CALL aws_oracle_ext.dbms_output$enable(buffer_size => NULL);

-- Step 2: Run your procedure
CALL hr.get_employee_data();

-- Step 3: Retrieve buffered output
SELECT * FROM aws_oracle_ext.dbms_output$get_lines(numlines => 1000);
```

**Recommended replacement** — native PostgreSQL:
```sql
RAISE NOTICE 'Employee ID: %, Name: % %, Email: %',
    v_employee_id, v_first_name, v_last_name, v_email;
```

> `aws_oracle_ext` is a migration scaffold. Replace with native PostgreSQL idioms in production code.

### 5.2 Partition Query Syntax

| Oracle | PostgreSQL (SCT output) |
|--------|------------------------|
| `SELECT * FROM sales PARTITION (sales_january)` | `SELECT * FROM sales_sales_january` |

SCT converts Oracle partition syntax to PostgreSQL partition child table names. Queries against partitions must reference the child table directly.

### 5.3 `SYSTEM_EVENTS` — Index-Organized Table (IOT)

Oracle:
```sql
CREATE TABLE SYSTEM_EVENTS (
    EVENT_ID NUMBER,
    ...
    CONSTRAINT PK_EVENT_ID PRIMARY KEY(EVENT_ID)
) ORGANIZATION INDEX;  -- IOT: physically ordered by PK
```

PostgreSQL — no native IOT; use `CLUSTER` to approximate:
```sql
CREATE TABLE SYSTEM_EVENTS (
    EVENT_ID NUMERIC,
    EVENT_CODE VARCHAR(10) NOT NULL,
    EVENT_DESCIPTION VARCHAR(200),
    EVENT_TIME DATE NOT NULL,
    CONSTRAINT PK_EVENT_ID PRIMARY KEY(EVENT_ID)
);

-- Physically reorder rows by PK (one-time operation)
CLUSTER SYSTEM_EVENTS USING PK_EVENT_ID;
```

> Note: `CLUSTER` is a one-time reorder, not maintained automatically. New inserts are not kept in order. Re-run `CLUSTER` periodically if physical ordering matters.

### 5.4 Identity / Sequence Columns

Oracle:
```sql
CREATE TABLE IDENTITY_TST (
    COL1 NUMBER GENERATED BY DEFAULT AS IDENTITY(START WITH 100 INCREMENT BY 10),
    COL2 VARCHAR2(30)
);
```

PostgreSQL equivalent:
```sql
CREATE TABLE SERIAL_SEQ_TST (
    COL1 SERIAL PRIMARY KEY,
    COL2 VARCHAR(10)
);

ALTER SEQUENCE SERIAL_SEQ_TST_COL1_SEQ RESTART WITH 100 INCREMENT BY 10;

INSERT INTO SERIAL_SEQ_TST(COL2) VALUES('A');
INSERT INTO SERIAL_SEQ_TST(COL1, COL2) VALUES(DEFAULT, 'B');
SELECT * FROM SERIAL_SEQ_TST;
```

### 5.5 `SUBSTR` — Index Difference

| Oracle | PostgreSQL |
|--------|-----------|
| `SUBSTR(col, 0, 1)` = 1 char from pos 0 (treated as 1) | `SUBSTR(col, 0, 1)` = empty string (pos 0 is before string) |
| `SUBSTR(col, 1, 1)` = 1 char from pos 1 | `SUBSTR(col, 1, 1)` = 1 char from pos 1 ✓ |

Always use **1-based indexing** in PostgreSQL:
```sql
-- Oracle
SELECT SUBSTR(rec.col1, 0, 1) FROM random_data_table;  -- works in Oracle

-- PostgreSQL equivalent
SELECT SUBSTR(col1, 1, 1) FROM random_data_table;
-- In PL/pgSQL:
RAISE NOTICE 'Substring: %', SUBSTR(rec.col1, 1, 5);
```

---

## 6. Data Type Mapping Reference

| Oracle Type | PostgreSQL Type | Notes |
|-------------|----------------|-------|
| `NUMBER(p,s)` | `NUMERIC(p,s)` | Direct equivalent |
| `NUMBER(*,0)` / `INTEGER` | `INTEGER` or `BIGINT` | Watch for decimal-formatted values in COPY |
| `VARCHAR2(n)` | `VARCHAR(n)` | Direct equivalent |
| `CHAR(n BYTE)` | `CHAR(n)` | Byte vs char semantics differ for multibyte |
| `DATE` | `TIMESTAMP` | Oracle DATE includes time component |
| `CLOB` | `TEXT` | SCT maps correctly |
| `NCLOB` | `TEXT` | PostgreSQL is UTF-8 natively |
| `BLOB` | `BYTEA` | DMS handles in Limited/Full LOB mode |
| `BFILE` | No equivalent | External file references; manual handling needed |
| `BINARY_FLOAT` | `REAL` | |
| `BINARY_DOUBLE` | `DOUBLE PRECISION` | |
| `FLOAT(n)` | `FLOAT(n)` | Oracle FLOAT is binary precision |
| `INTERVAL YEAR TO MONTH` | `INTERVAL` | |
| `INTERVAL DAY TO SECOND` | `INTERVAL` | |
| `TIMESTAMP WITH TIME ZONE` | `TIMESTAMP WITH TIME ZONE` | |
| `XMLTYPE` | `XML` | |
| `LONG` | `TEXT` | Deprecated in Oracle; migrate to CLOB first |
| `ROWID` / `UROWID` | No direct equivalent | Application logic change needed |
| `RAW(n)` | `BYTEA` | |
| `NCHAR` / `NVARCHAR2` | `CHAR` / `VARCHAR` | PostgreSQL is always Unicode |

### 6.1 Identity Column COPY Error

**Symptom:**
```
ERROR: invalid input syntax for type bigint: "100.0000000000"
COPY hr.identity_tst, line 1, column col1
```

**Cause:** Oracle exports `NUMBER` columns with decimal places (`100.0000000000`) even when the column is integer-typed. PostgreSQL `bigint` rejects this.

**Fix options:**
- Alter target column to `NUMERIC` before load, then cast after
- Pre-process the export file to strip decimal notation
- Use a DMS transformation rule to cast the column

---

## 7. PL/SQL → PL/pgSQL Conversion Patterns

### 7.1 Implicit Cursor FOR Loop (Minimal Conversion Needed)

Both Oracle and PostgreSQL support this pattern natively:

```sql
-- Oracle
FOR emp_rec IN (SELECT * FROM employees WHERE employee_id = 100) LOOP
    DBMS_OUTPUT.PUT_LINE('ID: ' || emp_rec.employee_id);
END LOOP;

-- PostgreSQL — same structure, different output call
FOR emp_rec IN SELECT * FROM hr.employees WHERE employee_id = 100 LOOP
    RAISE NOTICE 'ID: %', emp_rec.employee_id;
END LOOP;
```

### 7.2 Explicit Cursor

```sql
-- Oracle
CURSOR employee_cursor IS
    SELECT employee_id, first_name FROM employees WHERE employee_id = 100;
OPEN employee_cursor;
LOOP
    FETCH employee_cursor INTO v_id, v_name;
    EXIT WHEN employee_cursor%NOTFOUND;
    DBMS_OUTPUT.PUT_LINE(v_id || ' ' || v_name);
END LOOP;
CLOSE employee_cursor;

-- PostgreSQL
FOR emp_rec IN
    SELECT employee_id, first_name FROM hr.employees WHERE employee_id = 100
LOOP
    RAISE NOTICE '% %', emp_rec.employee_id, emp_rec.first_name;
END LOOP;
```

### 7.3 `NVL` → `COALESCE`

```sql
-- Oracle
SELECT NVL(column_with_null, 'Default_Value') FROM sample_table;

-- PostgreSQL
SELECT COALESCE(column_with_null, 'Default_Value') FROM sample_table;
```

In PL/pgSQL procedures:
```sql
-- Oracle procedure with NVL + DBMS_OUTPUT
CREATE OR REPLACE PROCEDURE sample_procedure AS
    v_value VARCHAR2(50);
BEGIN
    SELECT NVL(column_with_null, 'Default_Value') INTO v_value
    FROM sample_table WHERE id = 2;
    DBMS_OUTPUT.PUT_LINE('Result: ' || v_value);
END;

-- PostgreSQL function with COALESCE + RAISE NOTICE
CREATE OR REPLACE FUNCTION sample_function()
RETURNS VOID AS $$
DECLARE
    v_value VARCHAR;
BEGIN
    SELECT COALESCE(column_with_null, 'Default_Value') INTO v_value
    FROM sample_table WHERE id = 2;
    RAISE NOTICE 'Result: %', v_value;
END;
$$ LANGUAGE plpgsql;

SELECT sample_function();
```

### 7.4 CLOB Handling

```sql
-- Oracle: DBMS_LOB for large text construction
DECLARE
    large_text CLOB;
BEGIN
    DBMS_LOB.createtemporary(large_text, TRUE);
    DBMS_LOB.writeappend(large_text, LENGTH('text'), 'text');
    INSERT INTO clob_data_table VALUES (1, large_text);
    COMMIT;
END;

-- PostgreSQL: TEXT handles large content natively
INSERT INTO clob_data_table VALUES (1, repeat('text', 5000));
-- Or build dynamically:
DO $$
DECLARE
    large_text TEXT := '';
    i INTEGER := 1;
BEGIN
    WHILE i <= 5000 LOOP
        large_text := large_text || 'Sentence ' || i || ' of the long text ' || i || '. ';
        i := i + 1;
    END LOOP;
    INSERT INTO clob_data_table VALUES (1, large_text);
END;
$$;
```

### 7.5 PROCEDURE vs FUNCTION

PostgreSQL supports both, but idioms differ:

| Use Case | Oracle | PostgreSQL |
|----------|--------|-----------|
| No return value, DML | `PROCEDURE` | `PROCEDURE` (PG 11+) or `FUNCTION RETURNS VOID` |
| Return a single value | `FUNCTION` | `FUNCTION RETURNS type` |
| Return result set | `REF CURSOR` / pipelined | `FUNCTION RETURNS TABLE(...)` or `RETURNS SETOF` |
| Call syntax | `BEGIN proc; END;` | `CALL proc();` |
| Inspect source | `USER_SOURCE` | `\sf proc_name` or `\ef proc_name` |

---

## 8. Known Issues & Solutions

### 8.1 FK Constraint Violations During TRUNCATE

**Error:**
```
ERROR: cannot truncate a table referenced in a foreign key constraint
DETAIL: Table "locations" references "countries".
```
**Solution:** Use DMS "Drop tables on target" mode, or truncate all tables together with CASCADE.

### 8.2 `session_replication_role` Has No Effect on RDS

**Symptom:** Parameter group shows `session_replication_role = replica` as "Modified" but FK checks still fire.

**Root cause:** AWS blocks this parameter at the RDS instance level — it cannot be set as a default for all sessions via the parameter group.

**Verification:**
```sql
SHOW session_replication_role;
-- Returns: origin   (not replica)
```
**Solution:** Disable FKs explicitly per table, or use "Drop tables on target" in DMS.

### 8.3 `ORA-01031` on Supplemental Logging

**Error:** `ALTER DATABASE ADD SUPPLEMENTAL LOG DATA;` → `ORA-01031`

**Solution:**
```sql
EXEC rdsadmin.rdsadmin_util.alter_supplemental_logging('ADD');
```

### 8.4 `ORA-00942` on Table-Level Supplemental Logging

**Error:** Running `ALTER TABLE HR.EMPLOYEES ADD SUPPLEMENTAL LOG DATA...` as ADMIN fails.

**Solution:** Connect as the **schema owner (HR)** to run table-level supplemental logging commands.

### 8.5 FK Violation on `job_history` COPY

**Error:**
```
ERROR: insert or update on table "job_history" violates foreign key constraint "jhist_dept_fk"
DETAIL: Key (department_id)=(60) is not present in table "departments".
```
**Root cause:** `departments` was not yet loaded when `job_history` COPY ran (parallel load with FK dependencies).

**Solution:** Ensure parent tables are fully loaded before child tables, or disable FK constraints during bulk load.

### 8.6 BLOB Migration

The `BLOB_DATA_TABLE` insert pattern using `BFILENAME` does not migrate automatically via DMS. BLOBs read from Oracle filesystem paths are not accessible by DMS. Options:
- Pre-load BLOBs into the Oracle table as inline LOB data before DMS runs
- Use a custom migration script with `pg_lo_import` or application-layer copying

---

## 9. Post-Migration Validation

### 9.1 Row Count Verification

```sql
-- On Oracle source
SELECT table_name, num_rows
FROM all_tables
WHERE owner = 'HR'
ORDER BY table_name;

-- On PostgreSQL target
SELECT schemaname, tablename,
       n_live_tup AS estimated_rows
FROM pg_stat_user_tables
WHERE schemaname = 'hr'
ORDER BY tablename;

-- Exact counts (slower but accurate)
SELECT 'employees' AS tbl, COUNT(*) FROM hr.employees
UNION ALL
SELECT 'departments', COUNT(*) FROM hr.departments
UNION ALL
SELECT 'jobs', COUNT(*) FROM hr.jobs
-- ... etc
;
```

### 9.2 Verify Procedure Migration

```sql
-- Inspect migrated procedure source
\sf hr.get_employee_data

-- Edit interactively
\ef hr.get_employee_data

-- Test with aws_oracle_ext output retrieval
CALL aws_oracle_ext.dbms_output$enable(buffer_size => NULL);
CALL hr.get_employee_data();
SELECT * FROM aws_oracle_ext.dbms_output$get_lines(numlines => 1000);

-- Or after replacing with RAISE NOTICE:
SET client_min_messages = NOTICE;
CALL hr.get_employee_data();
```

### 9.3 Verify Sequence Continuity

```sql
SELECT sequence_name, last_value, increment_by, start_value
FROM information_schema.sequences
WHERE sequence_schema = 'hr';
```

### 9.4 CDC Verification

After enabling CDC and making a source change:
```sql
-- On Oracle: make a change
UPDATE hr.jobs SET max_salary = 100000 WHERE job_id = 'AD_PRES';
COMMIT;
EXEC rdsadmin.rdsadmin_util.switch_logfile;

-- On PostgreSQL: verify it replicated within expected latency
SELECT * FROM hr.jobs WHERE job_id = 'AD_PRES';
```

---

## 10. CDC Readiness Checklist

| # | Check | Verification Query / Command | Status |
|---|-------|------------------------------|--------|
| 1 | Archive log mode enabled | `SELECT log_mode FROM v$database;` → `ARCHIVELOG` | ✓ |
| 2 | Minimum supplemental logging ON | `SELECT supplemental_log_data_min FROM v$database;` → `YES` | ✓ |
| 3 | Table-level ALL COLUMNS supplemental logging | `SELECT log_group_name FROM all_log_groups WHERE owner='HR';` | ✓ |
| 4 | Primary keys present on all replicated tables | `SELECT table_name FROM all_tables WHERE owner='HR' MINUS SELECT table_name FROM all_constraints WHERE owner='HR' AND constraint_type='P';` | ✓ |
| 5 | Redo generated via DML | `UPDATE jobs SET max_salary=100000 WHERE job_id='AD_PRES'; COMMIT;` | ✓ |
| 6 | Log switch forced post-test | `EXEC rdsadmin.rdsadmin_util.switch_logfile;` | ✓ |
| 7 | DMS task configured for Full Load + CDC | DMS console → Task type | ✓ |
| 8 | CloudWatch logging enabled on DMS task | DMS console → Task settings | ✓ |
| 9 | Data validation enabled on DMS task | DMS console → Task settings | ✓ |
| 10 | Target FK handling confirmed | Row counts match; no constraint errors in logs | ✓ |

---

## Appendix: RDS Privilege Model Summary

| Operation | Oracle RDS User | Workaround |
|-----------|----------------|------------|
| `ALTER DATABASE ADD SUPPLEMENTAL LOG DATA` | ❌ ORA-01031 | `EXEC rdsadmin.rdsadmin_util.alter_supplemental_logging('ADD')` |
| `ALTER DATABASE ARCHIVELOG` | ❌ ORA-01031 | RDS is always in ARCHIVELOG mode |
| `SHUTDOWN IMMEDIATE` | ❌ ORA-01031 | Use RDS console for restarts |
| `ALTER SYSTEM SWITCH LOGFILE` | ❌ ORA-01031 (as HR) | `EXEC rdsadmin.rdsadmin_util.switch_logfile` (as ADMIN) |
| `ALTER TABLE ... ADD SUPPLEMENTAL LOG DATA` | ✓ as schema owner | Run as HR, not as ADMIN |
| `session_replication_role` (instance default) | N/A | ❌ Blocked by RDS — has no effect |
| `DISABLE TRIGGER ALL` | Requires `rds_superuser` on PG target | Grant `rds_superuser` to migration user |

---

*Document covers: Oracle RDS 19c → PostgreSQL RDS 18.3 | AWS DMS CDC | AWS SCT Extension Pack*
