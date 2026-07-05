# Phase 14 — Database Security

## 14.1 Database Users & Role-Based Access Control

Rather than every application component connecting as `root` or a single shared account, DEMS defines dedicated MySQL users mapped to the same role concept used inside the application (`roles` table). This is defense-in-depth: even if the application layer's own permission check has a bug, the database connection itself is restricted.

```sql
-- ----------------------------------------------------------------------------
-- Create role-mapped MySQL users (run as an admin/root account)
-- Passwords below are placeholders — replace with strong, generated secrets
-- pulled from a secrets manager, never hardcoded in scripts committed to source control.
-- ----------------------------------------------------------------------------

CREATE USER 'dems_admin'@'localhost'        IDENTIFIED BY 'REPLACE_WITH_STRONG_SECRET_1';
CREATE USER 'dems_supervisor'@'localhost'   IDENTIFIED BY 'REPLACE_WITH_STRONG_SECRET_2';
CREATE USER 'dems_investigator'@'localhost' IDENTIFIED BY 'REPLACE_WITH_STRONG_SECRET_3';
CREATE USER 'dems_custodian'@'localhost'    IDENTIFIED BY 'REPLACE_WITH_STRONG_SECRET_4';
CREATE USER 'dems_auditor'@'localhost'      IDENTIFIED BY 'REPLACE_WITH_STRONG_SECRET_5';
CREATE USER 'dems_app_service'@'%'          IDENTIFIED BY 'REPLACE_WITH_STRONG_SECRET_6';

-- ----------------------------------------------------------------------------
-- dems_admin: full administrative access (schema changes, user management)
-- ----------------------------------------------------------------------------
GRANT ALL PRIVILEGES ON dems_db.* TO 'dems_admin'@'localhost';

-- ----------------------------------------------------------------------------
-- dems_supervisor: full read + limited write (case/investigator management,
-- no ability to alter schema or touch audit_logs directly)
-- ----------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON dems_db.cases              TO 'dems_supervisor'@'localhost';
GRANT SELECT, INSERT, UPDATE ON dems_db.case_investigators  TO 'dems_supervisor'@'localhost';
GRANT SELECT, INSERT, UPDATE ON dems_db.case_departments    TO 'dems_supervisor'@'localhost';
GRANT SELECT ON dems_db.*                                   TO 'dems_supervisor'@'localhost';
GRANT EXECUTE ON PROCEDURE dems_db.sp_register_new_case     TO 'dems_supervisor'@'localhost';
GRANT EXECUTE ON PROCEDURE dems_db.sp_assign_investigator   TO 'dems_supervisor'@'localhost';
GRANT EXECUTE ON PROCEDURE dems_db.sp_close_case            TO 'dems_supervisor'@'localhost';

-- ----------------------------------------------------------------------------
-- dems_investigator: least privilege — can add/view evidence and transfer
-- custody through procedures only; NO direct table-level UPDATE/DELETE on
-- digital_evidence or chain_of_custody (forces all writes through the
-- validated stored procedures, where business rules and triggers apply).
-- ----------------------------------------------------------------------------
GRANT SELECT ON dems_db.*                                       TO 'dems_investigator'@'localhost';
GRANT EXECUTE ON PROCEDURE dems_db.sp_add_digital_evidence       TO 'dems_investigator'@'localhost';
GRANT EXECUTE ON PROCEDURE dems_db.sp_transfer_evidence          TO 'dems_investigator'@'localhost';
GRANT EXECUTE ON FUNCTION  dems_db.fn_evidence_count             TO 'dems_investigator'@'localhost';
GRANT EXECUTE ON FUNCTION  dems_db.fn_case_duration              TO 'dems_investigator'@'localhost';
GRANT EXECUTE ON FUNCTION  dems_db.fn_evidence_age               TO 'dems_investigator'@'localhost';
-- Explicitly NO direct INSERT/UPDATE/DELETE grants on digital_evidence or
-- chain_of_custody — all changes must go through the procedures above.

-- ----------------------------------------------------------------------------
-- dems_custodian: manages storage_locations and can execute transfer/archive
-- procedures, but cannot open/close cases or manage investigator assignments.
-- ----------------------------------------------------------------------------
GRANT SELECT ON dems_db.*                                    TO 'dems_custodian'@'localhost';
GRANT SELECT, UPDATE ON dems_db.storage_locations             TO 'dems_custodian'@'localhost';
GRANT EXECUTE ON PROCEDURE dems_db.sp_transfer_evidence       TO 'dems_custodian'@'localhost';
GRANT EXECUTE ON PROCEDURE dems_db.sp_archive_evidence        TO 'dems_custodian'@'localhost';

-- ----------------------------------------------------------------------------
-- dems_auditor: strictly read-only, across everything, including audit_logs
-- and chain_of_custody. No EXECUTE grants at all — an auditor should never
-- be able to trigger a state change, even indirectly through a procedure.
-- ----------------------------------------------------------------------------
GRANT SELECT ON dems_db.* TO 'dems_auditor'@'localhost';

-- ----------------------------------------------------------------------------
-- dems_app_service: the account the web/API backend actually connects with.
-- Scoped narrowly to only what the application needs — this account should
-- NEVER be handed out to a human directly.
-- ----------------------------------------------------------------------------
GRANT SELECT, INSERT ON dems_db.users                     TO 'dems_app_service'@'%';
GRANT SELECT ON dems_db.roles                              TO 'dems_app_service'@'%';
GRANT SELECT, INSERT ON dems_db.evidence_access_logs       TO 'dems_app_service'@'%';
GRANT SELECT ON dems_db.*                                  TO 'dems_app_service'@'%';
GRANT EXECUTE ON PROCEDURE dems_db.sp_register_new_case    TO 'dems_app_service'@'%';
GRANT EXECUTE ON PROCEDURE dems_db.sp_assign_investigator  TO 'dems_app_service'@'%';
GRANT EXECUTE ON PROCEDURE dems_db.sp_add_digital_evidence TO 'dems_app_service'@'%';
GRANT EXECUTE ON PROCEDURE dems_db.sp_transfer_evidence    TO 'dems_app_service'@'%';
GRANT EXECUTE ON PROCEDURE dems_db.sp_close_case           TO 'dems_app_service'@'%';
GRANT EXECUTE ON PROCEDURE dems_db.sp_archive_evidence     TO 'dems_app_service'@'%';

FLUSH PRIVILEGES;
```

## 14.2 Least Privilege Principle — how it's applied here

The recurring pattern above: **no role gets direct table-level write access to `digital_evidence` or `chain_of_custody`** except `dems_admin`. Every other role is forced through the stored procedures from Phase 9, which means:
- Status transitions are always validated (trigger enforcement can't be bypassed by a raw `UPDATE`).
- Chain-of-custody entries are always created with the correct structure.
- No one — not even a compromised investigator account — can silently edit a custody record or backdate a status change via direct SQL.

This is the practical meaning of "least privilege" in a database context: it's not just about which *tables* a role can see, but about **forcing sensitive writes through code paths that enforce business rules**, rather than leaving raw DML available.

## 14.3 Password Security Recommendations
- Store only salted, adaptive hashes (bcrypt, scrypt, or Argon2id) in `users.password_hash` — never MD5/SHA-1/plain SHA-256 for password storage (SHA-256 was used in the *sample data* for `file_hash`-style placeholders only, which is a completely different use case — integrity hashing, not password storage).
- Enforce a minimum length (12+ characters) and check against breached-password lists (e.g., HaveIBeenPwned's k-anonymity API) at the application layer — MySQL itself doesn't do this.
- MySQL-level accounts (`dems_admin`, etc.) should use MySQL's `caching_sha2_password` authentication plugin (the 8.0 default) and rotate credentials on a fixed schedule.
- Enable the `validate_password` component on the MySQL server itself for an extra enforcement layer on DB-level account passwords.

## 14.4 SQL Injection Prevention Guidelines
- **Always use parameterized queries/prepared statements** in the application layer — never string-concatenate user input into SQL, including inside dynamically-built `WHERE` clauses.
- The stored procedures in Phase 9 already reduce injection surface by accepting typed parameters (`INT UNSIGNED`, `VARCHAR(n)`, etc.) rather than raw strings the app assembles into SQL — MySQL's procedure parameter binding is inherently parameterized.
- Avoid `PREPARE`/dynamic SQL inside procedures unless absolutely necessary; none of the Phase 9 procedures use it.
- Apply strict input validation at the API layer (e.g., case numbers matching a fixed regex pattern) before values ever reach the database.
- Run the `dems_app_service` account with the narrow grants shown above — even in the worst case of a successful injection, the blast radius is limited to what that account can actually touch.

## 14.5 Backup Strategy
- **Full logical backup** nightly via `mysqldump --single-transaction --routines --triggers dems_db > backup_$(date +%F).sql` — `--single-transaction` avoids locking tables during backup (safe for InnoDB), and `--routines --triggers` ensures procedures/functions/triggers are captured, not just table data.
- **Binary log (binlog) enabled** continuously for point-in-time recovery between nightly backups — critical for a system where losing even a few hours of chain-of-custody entries would be a serious legal problem.
- Backups encrypted at rest and stored off-site/off-instance (e.g., a separate cloud storage account with restricted access) — a backup sitting unencrypted on the same server defeats much of its purpose.
- Retention: daily backups kept 30 days, weekly kept 12 months, in line with typical evidentiary retention expectations (actual retention should follow your jurisdiction's legal requirements, which this project doesn't attempt to specify).

## 14.6 Recovery Strategy
- Full restore procedure tested on a schedule (not just written and forgotten): `mysql dems_db < backup_file.sql`, then binlog replay from the backup's recorded position to the desired recovery point.
- Maintain a documented, rehearsed **Recovery Time Objective (RTO)** and **Recovery Point Objective (RPO)** — for a forensics system, RPO should be near-zero given binlog usage, since losing custody records is functionally similar to losing physical evidence tags.
- Keep a standby replica (MySQL replication) for faster failover in a production deployment — out of scope for this project's build, but worth naming as the natural next step.

## 14.7 Audit Logging Recommendations
- The `audit_logs` table (Phase 4) plus the triggers in Phase 11 already provide table-level change tracking — but audit logs are only trustworthy if they themselves can't be tampered with.
- `dems_auditor` (Section 14.1) gets `SELECT`-only access, including to `audit_logs` — **no role should ever have UPDATE/DELETE on `audit_logs`**, not even `dems_admin` in normal operation. If schema evolution requires modifying old audit rows, that should be a rare, manually logged, out-of-band DBA action.
- Consider forwarding `audit_logs` inserts to an external, append-only log aggregation system (e.g., a SIEM) in a production deployment, so that even a fully compromised database server can't retroactively erase its own audit trail.
- MySQL's own **audit plugin** (Enterprise Audit, or the open-source `audit_log` component) can supplement application-level `audit_logs` with connection-level logging (who connected, from where, when) — recommended as a defense-in-depth addition, not a replacement for the Phase 11 triggers.
