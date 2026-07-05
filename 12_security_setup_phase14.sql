-- ============================================================================
-- Enterprise Digital Evidence Management System (DEMS)
-- Phase 14: Database Security — Users, Roles & Grants (RUNNABLE VERSION)
-- MySQL 8.0
--
-- This is the executable SQL extracted from 10_security_phase14.md so it can
-- be run directly in MySQL Workbench like the other phase scripts.
-- The .md file still has the full written explanation (least privilege
-- reasoning, password/backup/recovery policy) — this file is JUST the code.
--
-- IMPORTANT: Replace every 'REPLACE_WITH_STRONG_SECRET_X' password below
-- with a real, strong password before running this outside a local test
-- environment. Run this as a root/admin MySQL account.
-- ============================================================================

USE dems_db;

-- ----------------------------------------------------------------------------
-- Drop these users first if re-running this script (safe to re-run)
-- ----------------------------------------------------------------------------
DROP USER IF EXISTS 'dems_admin'@'localhost';
DROP USER IF EXISTS 'dems_supervisor'@'localhost';
DROP USER IF EXISTS 'dems_investigator'@'localhost';
DROP USER IF EXISTS 'dems_custodian'@'localhost';
DROP USER IF EXISTS 'dems_auditor'@'localhost';
DROP USER IF EXISTS 'dems_app_service'@'%';

-- ----------------------------------------------------------------------------
-- Create role-mapped MySQL users
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
-- digital_evidence or chain_of_custody.
-- ----------------------------------------------------------------------------
GRANT SELECT ON dems_db.*                                       TO 'dems_investigator'@'localhost';
GRANT EXECUTE ON PROCEDURE dems_db.sp_add_digital_evidence       TO 'dems_investigator'@'localhost';
GRANT EXECUTE ON PROCEDURE dems_db.sp_transfer_evidence          TO 'dems_investigator'@'localhost';
GRANT EXECUTE ON FUNCTION  dems_db.fn_evidence_count             TO 'dems_investigator'@'localhost';
GRANT EXECUTE ON FUNCTION  dems_db.fn_case_duration              TO 'dems_investigator'@'localhost';
GRANT EXECUTE ON FUNCTION  dems_db.fn_evidence_age               TO 'dems_investigator'@'localhost';

-- ----------------------------------------------------------------------------
-- dems_custodian: manages storage_locations and can execute transfer/archive
-- procedures, but cannot open/close cases or manage investigator assignments.
-- ----------------------------------------------------------------------------
GRANT SELECT ON dems_db.*                                    TO 'dems_custodian'@'localhost';
GRANT SELECT, UPDATE ON dems_db.storage_locations             TO 'dems_custodian'@'localhost';
GRANT EXECUTE ON PROCEDURE dems_db.sp_transfer_evidence       TO 'dems_custodian'@'localhost';
GRANT EXECUTE ON PROCEDURE dems_db.sp_archive_evidence        TO 'dems_custodian'@'localhost';

-- ----------------------------------------------------------------------------
-- dems_auditor: strictly read-only, across everything including audit_logs
-- and chain_of_custody. No EXECUTE grants at all.
-- ----------------------------------------------------------------------------
GRANT SELECT ON dems_db.* TO 'dems_auditor'@'localhost';

-- ----------------------------------------------------------------------------
-- dems_app_service: the account the web/API backend connects with. Scoped
-- narrowly to only what the application needs.
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

-- ============================================================================
-- Verification queries (run after the above to confirm grants took effect)
-- ============================================================================
-- SHOW GRANTS FOR 'dems_investigator'@'localhost';
-- SHOW GRANTS FOR 'dems_auditor'@'localhost';
-- SELECT user, host FROM mysql.user WHERE user LIKE 'dems_%';

-- ============================================================================
-- END OF PHASE 14 SECURITY SETUP SCRIPT
-- ============================================================================
