# Enterprise Digital Evidence Management System (DEMS)  🔐 

A fully normalized **MySQL 8.0** relational database for managing cybercrime investigation cases, digital evidence, chain of custody, and audit compliance across a multi-department Cyber Crime Investigation Unit.

![MySQL](https://img.shields.io/badge/MySQL-8.0-4479A1?style=flat&logo=mysql&logoColor=white)
![Status](https://img.shields.io/badge/status-complete-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

## 📖 About

DEMS models the complete lifecycle of digital evidence — from seizure and intake through forensic analysis, custody transfers, court submission, and archival — while enforcing the legal integrity requirements real forensics labs operate under: an unbroken chain of custody, full audit trails, and role-based access control.

Built as a final-year database engineering project demonstrating:
- 3NF-normalized relational design (18 tables)
- Stored procedures, triggers, and functions enforcing real business rules
- Transaction-safe operations with rollback demonstrations
- Role-based database security (least privilege)
- 30+ advanced SQL queries (joins, CTEs, window functions)


## 🗂️ Project Structure

```
dems/
├── README.md
├── 01_schema_phase5.sql              # CREATE DATABASE + 18 tables, constraints, indexes
├── 02_sample_data_phase6.sql         # 1,265 realistic sample records
├── 03_queries_phase7.sql             # 36 advanced SQL queries
├── 04_views_phase8.sql               # 7 reporting views
├── 05_procedures_phase9.sql          # 6 stored procedures
├── 06_functions_phase10.sql          # 4 reusable SQL functions
├── 07_triggers_phase11.sql           # 6 triggers (audit, integrity, workflow)
├── 08_transactions_phase12.sql       # Transaction / rollback demonstrations
├── 09_indexes_phase13.md             # Index design rationale
├── 10_security_phase14.md            # Security policy write-up
├── 12_security_setup_phase14.sql     # Runnable users/roles/GRANT script
├── 11_testing_phase15.md             # Test scenarios + expected outputs
└── docs/
    └── project_intro.md              # Phase 1-4: overview, ER design, schema docs
```

## 🏗️ Entity Overview

18 tables across 4 categories:

| Category | Tables |
|---|---|
| **Reference/Lookup** | departments, roles, evidence_categories, evidence_types, evidence_status, storage_locations |
| **Core Entities** | users, investigators, cases, suspects, devices, digital_evidence |
| **Junctions** | case_departments, case_investigators, case_suspects |
| **Logs (append-only)** | chain_of_custody, evidence_access_logs, audit_logs |

---

## ⚙️ Setup & Installation

### Prerequisites
- MySQL **8.0+** 
- MySQL client

### Run in order:

```bash
mysql -u root -p < 01_schema_phase5.sql
mysql -u root -p dems_db < 02_sample_data_phase6.sql
mysql -u root -p dems_db < 04_views_phase8.sql
mysql -u root -p dems_db < 05_procedures_phase9.sql
mysql -u root -p dems_db < 06_functions_phase10.sql
mysql -u root -p dems_db < 07_triggers_phase11.sql
mysql -u root -p dems_db < 03_queries_phase7.sql
mysql -u root -p dems_db < 08_transactions_phase12.sql
mysql -u root -p < 12_security_setup_phase14.sql   # edit placeholder passwords first!
```

### Verify installation:
```sql
USE dems_db;
SHOW TABLES;                                    -- expect 18
SELECT COUNT(*) FROM digital_evidence;          -- expect 120
SHOW TRIGGERS;                                  -- expect 6
SHOW PROCEDURE STATUS WHERE Db = 'dems_db';      -- expect 6
SHOW FUNCTION STATUS WHERE Db = 'dems_db';       -- expect 4
```


## 🧠 Key Design Highlights

- **Chain of custody as source of truth** — a trigger auto-syncs `digital_evidence.current_location_id` whenever a new custody record is inserted, instead of maintaining two independently-updated copies of "where is it now."
- **Status transitions are enforced, not just suggested** — a trigger blocks evidence from moving backward through its lifecycle (e.g., Archived → Collected is physically rejected by the database).
- **Least-privilege roles** — investigators have no direct write access to evidence tables; all writes are forced through validated stored procedures.
- **Multi-department case sharing** — junction tables (`case_departments`, `case_investigators`, `case_suspects`) model the real-world reality that cases span more than one team.


## 🧪 Testing

See [`11_testing_phase15.md`](./11_testing_phase15.md) for 13 test scenarios covering constraint violations, trigger behavior, procedure business rules, and transaction rollback integrity — each with the exact expected error code/output.


## 👤 Author

Built as a final-year database engineering / cybersecurity portfolio project.
