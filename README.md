# Enterprise Digital Evidence Management System (DEMS)

A fully normalized MySQL 8.0 relational database for managing cybercrime investigation cases, digital evidence, chain of custody, and audit compliance across a multi-department Cyber Crime Investigation Unit.

---

## Project Overview

DEMS models the complete lifecycle of digital evidence — from seizure and intake through forensic analysis, custody transfers, court submission, and archival — while enforcing the legal integrity requirements real forensics labs operate under (unbroken chain of custody, full audit trails, role-based access control).

See `00_project_intro_and_requirements.md` for the full problem statement, objectives, and scope (multi-department case-sharing model).

---

## Project Structure

```
dems/
├── README.md                          (this file)
├── 00_project_intro_and_requirements.md   Phase 1-4 write-up (intro, functional reqs, ER design, schema)
├── 01_schema_phase5.sql               CREATE DATABASE + all 18 tables, constraints, indexes
├── 02_sample_data_phase6.sql          1,265 realistic INSERT/UPDATE statements
├── 03_queries_phase7.sql              36 advanced SQL queries (joins, CTEs, window functions, reports)
├── 04_views_phase8.sql                7 reporting views
├── 05_procedures_phase9.sql           6 stored procedures (case/evidence lifecycle operations)
├── 06_functions_phase10.sql           4 reusable scalar functions
├── 07_triggers_phase11.sql            6 triggers (audit, integrity, workflow automation)
├── 08_transactions_phase12.sql        Transaction/rollback/savepoint demonstrations
├── 09_indexes_phase13.md              Index rationale (indexes themselves live in phase5 script)
├── 10_security_phase14.md             Users, RBAC grants, password/injection/backup/recovery policy
├── 11_testing_phase15.md              13 test scenarios with expected outputs + test log template
└── (this README)                      Phase 16
```

> Note: This README references `00_project_intro_and_requirements.md` for the Phase 1–4 narrative content, which was delivered in-conversation rather than as a standalone file. If you want that content as an actual file in this folder, say so and I'll generate it — everything else above is already a real file in your outputs.

---

## Installation & Database Setup

### Prerequisites
- MySQL 8.0 or later (CHECK constraints and window functions require 8.0+; this will **not** work correctly on MySQL 5.7)
- A MySQL client (`mysql` CLI, MySQL Workbench, DBeaver, etc.)
- Sufficient privileges to `CREATE DATABASE` and `CREATE USER`

### Setup Steps

1. **Create the schema:**
   ```bash
   mysql -u root -p < 01_schema_phase5.sql
   ```
   This drops any existing `dems_db`, recreates it, and builds all 18 tables with constraints and indexes.

2. **Load sample data:**
   ```bash
   mysql -u root -p dems_db < 02_sample_data_phase6.sql
   ```

3. **Create views:**
   ```bash
   mysql -u root -p dems_db < 04_views_phase8.sql
   ```

4. **Create stored procedures:**
   ```bash
   mysql -u root -p dems_db < 05_procedures_phase9.sql
   ```

5. **Create functions:**
   ```bash
   mysql -u root -p dems_db < 06_functions_phase10.sql
   ```

6. **Create triggers:**
   ```bash
   mysql -u root -p dems_db < 07_triggers_phase11.sql
   ```
   > Run this **after** sample data is loaded — the triggers include a "prevent delete on active case" rule and status-transition validation that could otherwise interfere with the bulk sample-data load if created first (the sample data script re-numbers/updates rows as part of its custody reconciliation step, and the triggers would fire on every one of those UPDATEs).

7. **(Optional) Apply security roles/grants:**
   ```bash
   mysql -u root -p < 10_security_phase14.md   # copy the SQL block out first — this file is markdown, not raw SQL
   ```
   Replace every placeholder password before running this in any real environment.

8. **Run the query library / test transactions as needed:**
   ```bash
   mysql -u root -p dems_db < 03_queries_phase7.sql
   mysql -u root -p dems_db < 08_transactions_phase12.sql
   ```

### Verifying the install
```sql
USE dems_db;
SHOW TABLES;                      -- should list 18 tables
SELECT COUNT(*) FROM digital_evidence;   -- should return 120
SELECT COUNT(*) FROM chain_of_custody;   -- should return 259
SHOW TRIGGERS;                    -- should list 6 triggers
SHOW PROCEDURE STATUS WHERE Db = 'dems_db';  -- should list 6 procedures
SHOW FUNCTION STATUS WHERE Db = 'dems_db';   -- should list 4 functions
```

---

## Screenshots Required (for your submission)

Since this is a database-layer project without a UI, your report/demo should include screenshots of:
1. `SHOW TABLES;` output confirming all 18 tables
2. An ER diagram exported from MySQL Workbench (File → Export → ... after reverse-engineering the schema) or a tool like dbdiagram.io fed from the schema
3. Output of a few representative queries from `03_queries_phase7.sql` (especially the window function and CTE ones — they demonstrate the most SQL sophistication)
4. A trigger firing in real time — e.g., Test 6 from `11_testing_phase15.md` (custody insert auto-syncing evidence location), showing the `SELECT` before and after
5. A blocked operation — e.g., Test 3 or Test 4 (deletion/backward-transition errors), showing the actual `ERROR 1644` message
6. `EXPLAIN` output on one or two queries before/after an index was added, if you want to demonstrate the performance impact discussed in Phase 13

---

## Known Limitations & Future Improvements

Documented honestly here rather than glossed over, since a reviewer will find these anyway:

- **Table count (18) exceeds the original 12–15 guideline.** This is a direct, deliberate consequence of the multi-department scope decision — three additional junction tables (`case_departments`, `case_investigators`, `case_suspects`) were required to model many-to-many relationships properly rather than denormalizing them onto the `cases` table.
- **`sp_add_digital_evidence`'s evidence-code sequence generator** (`COUNT(*) + 1`) has a known race condition under concurrent writes — acceptable for this project's scale, but flagged as needing a proper sequence table with row locking in a production deployment.
- **No UI/API layer** — this is a database-only deliverable. A natural next step is a REST API (e.g., FastAPI/Express) sitting on top of the stored procedures, so the application layer never issues raw DML at all.
- **No inter-agency/cross-organization sharing** — the multi-department model covers departments *within* one investigative unit, not sharing evidence data with an entirely separate organization's database. That would need a federation or export/import protocol, explicitly out of scope here.
- **Evidence file storage is metadata-only** — actual evidence files (disk images, PCAPs, etc.) would live in a separate object store (e.g., S3 with object lock/WORM storage) referenced by `file_hash`, not inside MySQL itself.
- **Full-text/fuzzy search** on suspect names or evidence descriptions isn't implemented (noted in Phase 13) — would need a `FULLTEXT` index or an external search engine for real usability at scale.
- **No automated test suite** — Phase 15's scenarios are manual/documented, not wired into a CI pipeline. A logical next step would be a set of `mysql-test-run` or application-level integration tests that execute all 13 scenarios automatically on every schema change.

---

## Coding Standards Followed
- MySQL 8.0 syntax throughout (CHECK constraints, window functions, JSON columns)
- Consistent naming: `snake_case` for all tables/columns, `sp_` prefix for procedures, `fn_` prefix for functions, `trg_` prefix for triggers, `vw_` prefix for views, `idx_`/`uq_`/`chk_`/`fk_` prefixes for constraints/indexes
- Every script is commented and sectioned to match this document's phase structure
- Referential integrity enforced via FK constraints first, triggers second (defense-in-depth, not either/or)
