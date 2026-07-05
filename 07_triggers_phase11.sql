-- ============================================================================
-- Enterprise Digital Evidence Management System (DEMS)
-- Phase 11: Triggers
-- MySQL 8.0
-- ============================================================================
-- This phase assumes the schema/tables built in Phases 1-10:
--   cases(case_id, case_number, title, case_status, date_opened, date_closed, ...)
--   digital_evidence(evidence_id, case_id, evidence_code, status,
--                     date_collected, current_location_id, ...)
--   chain_of_custody(custody_id, evidence_id, custodian_id, location_id,
--                     transfer_time, confirmed, notes, ...)
--   investigators(investigator_id, full_name, ...)
--   case_investigators(case_id, investigator_id, role)
--
-- If your actual column names differ slightly from Phases 1-10, adjust the
-- triggers below accordingly — the logic/pattern is what matters for grading.
-- ============================================================================
USE dems_db;

-- ----------------------------------------------------------------------------
-- Support table: audit_log
-- Purpose: Generic append-only audit trail written to by trigger 1 below.
-- Created here with IF NOT EXISTS in case it wasn't part of an earlier phase.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
    log_id        BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    table_name    VARCHAR(64)     NOT NULL,
    record_id     INT UNSIGNED    NOT NULL,
    action        ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    old_values    JSON            NULL,
    new_values    JSON            NULL,
    changed_by    VARCHAR(128)    NOT NULL DEFAULT (CURRENT_USER()),
    changed_at    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_audit_table_record (table_name, record_id)
) ENGINE=InnoDB;

-- ============================================================================
-- Trigger Set 1: Audit logging on digital_evidence
-- Purpose: Record every INSERT/UPDATE/DELETE on digital_evidence into
--          audit_log as JSON snapshots, so any change to an evidence record
--          is traceable — a core requirement for chain-of-custody defensibility.
-- ============================================================================
DELIMITER $$

CREATE TRIGGER trg_evidence_audit_insert
AFTER INSERT ON digital_evidence
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values)
    VALUES (
        'digital_evidence',
        NEW.evidence_id,
        'INSERT',
        NULL,
        JSON_OBJECT(
            'evidence_id', NEW.evidence_id,
            'case_id', NEW.case_id,
            'evidence_code', NEW.evidence_code,
            'status', NEW.status,
            'current_location_id', NEW.current_location_id
        )
    );
END$$

CREATE TRIGGER trg_evidence_audit_update
AFTER UPDATE ON digital_evidence
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values)
    VALUES (
        'digital_evidence',
        NEW.evidence_id,
        'UPDATE',
        JSON_OBJECT(
            'status', OLD.status,
            'current_location_id', OLD.current_location_id
        ),
        JSON_OBJECT(
            'status', NEW.status,
            'current_location_id', NEW.current_location_id
        )
    );
END$$

CREATE TRIGGER trg_evidence_audit_delete
BEFORE DELETE ON digital_evidence
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values)
    VALUES (
        'digital_evidence',
        OLD.evidence_id,
        'DELETE',
        JSON_OBJECT(
            'evidence_id', OLD.evidence_id,
            'case_id', OLD.case_id,
            'evidence_code', OLD.evidence_code,
            'status', OLD.status
        ),
        NULL
    );
END$$

DELIMITER ;

-- ============================================================================
-- Trigger 2: Prevent deletion of evidence linked to an active case
-- Purpose: Evidence tied to a case that is still open (i.e. not closed or
--          archived) should never be hard-deleted — that would destroy the
--          record a court proceeding may still depend on. Deletion is only
--          permitted once the parent case is closed/archived (and even then,
--          sp_archive_evidence from Phase 9 is the intended path).
-- Note: this fires BEFORE DELETE, so it runs before trg_evidence_audit_delete
--       above and can block the delete outright via SIGNAL.
-- ============================================================================
DELIMITER $$

CREATE TRIGGER trg_prevent_evidence_deletion
BEFORE DELETE ON digital_evidence
FOR EACH ROW
BEGIN
    DECLARE v_case_status VARCHAR(32);

    SELECT case_status INTO v_case_status
    FROM cases
    WHERE case_id = OLD.case_id;

    IF v_case_status IS NOT NULL AND v_case_status NOT IN ('closed', 'archived') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot delete evidence linked to an active case. Close or archive the case first.';
    END IF;
END$$

DELIMITER ;

-- ============================================================================
-- Trigger 3: Auto-record custody transfers
-- Purpose: Whenever digital_evidence.current_location_id (i.e. who/where the
--          item currently sits with) changes, automatically insert a row
--          into chain_of_custody rather than relying on every caller to
--          remember to do it manually. This is a safety net that complements
--          sp_transfer_evidence from Phase 9 (which already writes a custody
--          row) — this trigger guarantees the log stays consistent even if a
--          location change happens through some other code path.
-- ============================================================================
DELIMITER $$

CREATE TRIGGER trg_auto_custody_transfer
AFTER UPDATE ON digital_evidence
FOR EACH ROW
BEGIN
    IF NOT (OLD.current_location_id <=> NEW.current_location_id) THEN
        INSERT INTO chain_of_custody (
            evidence_id, custodian_id, location_id, transfer_time, confirmed, notes
        )
        VALUES (
            NEW.evidence_id,
            NULL,
            NEW.current_location_id,
            NOW(),
            FALSE,
            'Auto-logged by trg_auto_custody_transfer due to location change'
        );
    END IF;
END$$

DELIMITER ;

-- ============================================================================
-- Trigger 4: Update case status on evidence submission
-- Purpose: When a piece of evidence transitions into 'Submitted' status,
--          check whether every evidence item on that case is now Submitted
--          or Court-Ready. If so, and the case isn't already closed/archived,
--          bump case_status to 'pending-closure' so investigators/reviewers
--          know the case is ready for sign-off — without forcing anyone to
--          poll evidence tables manually.
-- ============================================================================
DELIMITER $$

CREATE TRIGGER trg_case_status_on_submission
AFTER UPDATE ON digital_evidence
FOR EACH ROW
BEGIN
    DECLARE v_outstanding INT UNSIGNED;
    DECLARE v_case_status VARCHAR(32);

    IF NEW.status = 'Submitted' AND OLD.status <> 'Submitted' THEN

        SELECT COUNT(*) INTO v_outstanding
        FROM digital_evidence
        WHERE case_id = NEW.case_id
          AND status NOT IN ('Submitted', 'Court-Ready');

        SELECT case_status INTO v_case_status
        FROM cases
        WHERE case_id = NEW.case_id;

        IF v_outstanding = 0 AND v_case_status NOT IN ('closed', 'archived') THEN
            UPDATE cases
            SET case_status = 'pending-closure'
            WHERE case_id = NEW.case_id;
        END IF;
    END IF;
END$$

DELIMITER ;

-- ============================================================================
-- Trigger 5: Validate evidence status transitions
-- Purpose: Enforce the evidence lifecycle state machine at the database
--          layer so a status update can't skip stages or move backward in a
--          way that would be inconsistent with the chain-of-custody story:
--
--            Collected -> Under Analysis -> Court-Ready -> Submitted
--
--          Archived is a terminal state reachable only from Submitted or
--          Court-Ready (mirrors the sp_archive_evidence business rule from
--          Phase 9). Any other jump raises an error instead of silently
--          corrupting the lifecycle.
-- Note: this must be BEFORE UPDATE so it can reject the change before it
--       is written (and therefore before trg_auto_custody_transfer and
--       trg_case_status_on_submission fire on the same row).
-- ============================================================================
DELIMITER $$

CREATE TRIGGER trg_validate_status_transition
BEFORE UPDATE ON digital_evidence
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN
        IF NOT (
            (OLD.status = 'Collected'       AND NEW.status = 'Under Analysis') OR
            (OLD.status = 'Under Analysis'  AND NEW.status = 'Court-Ready')   OR
            (OLD.status = 'Under Analysis'  AND NEW.status = 'Collected')     OR
            (OLD.status = 'Court-Ready'     AND NEW.status = 'Submitted')     OR
            (OLD.status = 'Court-Ready'     AND NEW.status = 'Under Analysis') OR
            (OLD.status = 'Submitted'       AND NEW.status = 'Archived')      OR
            (OLD.status = 'Court-Ready'     AND NEW.status = 'Archived')
        ) THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Invalid evidence status transition.';
        END IF;
    END IF;
END$$

DELIMITER ;

-- ============================================================================
-- Notes for your defense
-- ============================================================================
-- 1. Trigger ORDER matters here. MySQL fires same-timing triggers on the same
--    table in the order they were created (you can also use FOLLOWS/PRECEDES
--    in MySQL 8.0 to make this explicit). We rely on:
--      BEFORE UPDATE: trg_prevent_evidence_deletion (delete only, N/A here)
--      BEFORE UPDATE: trg_validate_status_transition   <- must run first,
--                      so an invalid transition never reaches the other
--                      AFTER UPDATE triggers.
--      AFTER UPDATE:  trg_evidence_audit_update, trg_auto_custody_transfer,
--                      trg_case_status_on_submission
--    If you want this guaranteed rather than "creation order," add:
--      ALTER TRIGGER ... -- (not supported in MySQL; instead use
--      CREATE TRIGGER ... FOLLOWS trg_x  /  PRECEDES trg_y
--    when you first create each trigger.
--
-- 2. trg_auto_custody_transfer inserts custodian_id = NULL and confirmed =
--    FALSE, deliberately, because the trigger doesn't know *who* initiated
--    the change (there's no session/application user context passed into a
--    raw UPDATE). sp_transfer_evidence (Phase 9) is still the preferred path
--    for real transfers since it writes a complete, confirmed row with the
--    actual custodian — this trigger is a safety net, not the primary path.
--    That's also why vw_chain_of_custody_summary's "unconfirmed-transfer
--    flag" (Phase 8) is useful: it will surface any row this trigger created
--    that never got reconciled by a proper procedure call.
--
-- 3. trg_case_status_on_submission introduces a new case_status value,
--    'pending-closure'. If your cases.case_status column is an ENUM rather
--    than VARCHAR, you'll need to ALTER TABLE cases MODIFY COLUMN
--    case_status ENUM(...,'pending-closure',...) first, or this trigger
--    will throw a data-truncation error on the UPDATE.
--
-- 4. All BEFORE-timing SIGNALs here (deletion prevention, invalid status
--    transition) cause the entire triggering statement to roll back, which
--    is exactly the desired behavior — same "fail loudly on explicit
--    actions" philosophy used in the Phase 9 procedures.
-- ============================================================================

-- ============================================================================
-- END OF PHASE 11 TRIGGERS
-- ============================================================================
