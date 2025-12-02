# PostgreSQL Users, Roles & Privilege Inheritance — Complete Demonstration

## 📘 Overview
PostgreSQL’s role-based security model is powerful yet often misunderstood.  
This guide provides a complete hands-on demonstration showing:

- How to create users and group roles  
- How table and column privileges work  
- How users inherit privileges through roles  
- How to audit privileges using `information_schema`  
- How to trace effective privileges with a Privilege Lineage Inspector  

This is ideal for DBAs, developers, trainers, and security teams.

---

# 🚀 1. Setup

```sql
CREATE DATABASE demo_privs;
\c demo_privs;
```

---

# 🚀 2. Create Schemas & Tables

```sql
CREATE SCHEMA hr;
CREATE TABLE hr.employees(
    id SERIAL PRIMARY KEY,
    name TEXT,
    salary INT
);

CREATE SCHEMA finance;
CREATE TABLE finance.invoices(
    id SERIAL PRIMARY KEY,
    amount INT,
    created_on TIMESTAMPTZ DEFAULT now()
);
```

---

# 🚀 3. Create Users

```sql
CREATE ROLE alice LOGIN PASSWORD 'alice123';
CREATE ROLE bob   LOGIN PASSWORD 'bob123';
```

---

# 🚀 4. Create Group Roles

```sql
CREATE ROLE reporting_group;
CREATE ROLE finance_group;
```

Group roles hold privileges. Users inherit those privileges.

---

# 🚀 5. Grant Privileges to Roles

### Reporting team privileges:
```sql
GRANT USAGE ON SCHEMA hr TO reporting_group;
GRANT SELECT ON hr.employees TO reporting_group;
```

### Finance team privileges:
```sql
GRANT USAGE ON SCHEMA finance TO finance_group;
GRANT SELECT, INSERT ON finance.invoices TO finance_group;
```

### Column-level privilege example:
```sql
GRANT SELECT(name) ON hr.employees TO reporting_group;
```

---

# 🚀 6. Assign Users to Roles

```sql
GRANT reporting_group TO alice;
GRANT finance_group   TO bob;
```

Optional nested inheritance:

```sql
GRANT reporting_group TO finance_group;
```

---

# 🚀 7. Test the Privileges

## Alice
```sql
SET ROLE alice;
SELECT * FROM hr.employees;      -- works
SELECT * FROM finance.invoices;  -- fails unless inherited
RESET ROLE;
```

## Bob
```sql
SET ROLE bob;
SELECT * FROM finance.invoices;                -- works
INSERT INTO finance.invoices(amount) VALUES(5); -- works
SELECT * FROM hr.employees;                     -- works only if role nesting enabled
RESET ROLE;
```

---

# 🛠️ 8. Privilege Inspection Toolkit

## 8.1 Role Membership Tree
```sql
WITH RECURSIVE role_tree AS (
    SELECT r.oid, r.rolname AS role, r.rolname AS member_of
    FROM pg_roles r
    WHERE r.rolname = 'alice'

    UNION ALL

    SELECT am.member, parent.rolname, rt.member_of
    FROM pg_auth_members am
    JOIN pg_roles parent ON parent.oid = am.roleid
    JOIN role_tree rt ON rt.oid = am.member
)
SELECT DISTINCT role, member_of
FROM role_tree
ORDER BY role;
```

---

## 8.2 Table Privileges

```sql
SELECT 
    grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee IN ('alice','bob','reporting_group','finance_group')
ORDER BY grantee, table_schema, table_name;
```

---

## 8.3 Schema Privileges

```sql
SELECT 
    grantee, schema_name, privilege_type
FROM information_schema.schema_privileges
WHERE grantee IN ('alice','bob','reporting_group','finance_group')
ORDER BY grantee, schema_name;
```

---

## 8.4 Column Privileges

```sql
SELECT
    grantee, table_schema, table_name, column_name, privilege_type
FROM information_schema.column_privileges
WHERE grantee IN ('alice','bob','reporting_group','finance_group')
ORDER BY grantee, table_schema, table_name;
```

---

## 8.5 Full Grant Audit

```sql
SELECT
    table_schema, table_name, grantee, privilege_type, grantor
FROM information_schema.role_table_grants
ORDER BY table_schema, table_name, grantee;
```

---

# 🔥 9. Ultimate Privilege Lineage Inspector

This query shows **exactly** which privileges a user gets from each inherited role.

```sql
WITH RECURSIVE inherited_roles AS (
    SELECT r.rolname AS user_name, r.rolname AS role_name
    FROM pg_roles r
    WHERE r.rolname = 'alice'

    UNION ALL

    SELECT ir.user_name, parent.rolname
    FROM inherited_roles ir
    JOIN pg_auth_members am 
        ON am.member = (SELECT oid FROM pg_roles WHERE rolname = ir.role_name)
    JOIN pg_roles parent ON parent.oid = am.roleid
),
privs AS (
    SELECT grantee, table_schema, table_name, privilege_type
    FROM information_schema.role_table_grants
)
SELECT 
    ir.user_name AS user,
    ir.role_name AS privilege_from_role,
    p.table_schema,
    p.table_name,
    p.privilege_type
FROM inherited_roles ir
JOIN privs p ON p.grantee = ir.role_name
ORDER BY privilege_from_role, table_schema, table_name;
```

---

# 🧠 Key Takeaways

- PostgreSQL users are roles with LOGIN
- Privileges belong to roles, not users
- Users inherit privileges automatically
- Column-level privileges are supported and powerful
- Auditing privileges requires looking at:  
  - `pg_auth_members`  
  - `information_schema.*_privileges`  
  - Role inheritance chains  
- The Privilege Lineage Inspector helps understand “who gets what from where”

---

# 🎉 Conclusion

This demonstration provides an end-to-end explanation of PostgreSQL’s role and privilege system.  
You now have:

✔ A full working demo  
✔ Auditing scripts  
✔ Role inheritance inspection  
✔ Column-level privilege examples  
✔ A GitHub-ready reference for training or documentation  

Feel free to extend this demo with:

- Row-Level Security (RLS)  
- Default Privileges  
- Dynamic Privilege Auditing  
- Multi-tenant access models  

Happy learning and hacking with PostgreSQL! 🐘
