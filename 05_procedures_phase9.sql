-- ============================================================================
-- Enterprise Digital Evidence Management System (DEMS)
-- Phase 9: Stored Procedures (6 procedures)
-- MySQL 8.0
-- ============================================================================
USE dems_db;

-- ----------------------------------------------------------------------------
-- Procedure 1: sp_register_new_case
-- Purpose: Opens a new case, validates FK inputs, and auto-links the
--          originating department + lead investigator into their junction
--          tables in one atomic operation.
-- ----------------------------------------------------------------------------
DELIMITER $$

CREATE PROCEDURE sp_register_new_case (
    IN  p_case_number     VARCHAR(20),
    IN  p_title           VARCHAR(200),
    IN  p_description     TEXT,
    IN  p_department_id   INT UNSIGNED,
    IN  p_lead_investigator_id INT UNSIGNED,
    IN  p_case_type       VARCHAR(30),
    IN  p_priority        VARCHAR(10),
    OUT p_new_case_id     INT UNSIGNED
)
BEGIN
    DECLARE v_dept_exists INT DEFAULT 0;
    DECLARE v_inv_exists  INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT COUNT(*) INTO v_dept_exists FROM departments WHERE department_id = p_department_id;
    SELECT COUNT(*) INTO v_inv_exists  FROM investigators WHERE investigator_id = p_lead_investigator_id;

    IF v_dept_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sp_register_new_case: department_id does not exist';
    END IF;

    IF v_inv_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sp_register_new_case: lead_investigator_id does not exist';
    END IF;

    START TRANSACTION;

    INSERT INTO cases (case_number, title, description, originating_department_id,
                        lead_investigator_id, case_type, priority, case_status, date_opened)
    VALUES (p_case_number, p_title, p_description, p_department_id,
            p_lead_investigator_id, p_case_type, p_priority, 'open', CURDATE());

    SET p_new_case_id = LAST_INSERT_ID();

    INSERT INTO case_departments (case_id, department_id, involvement_role, date_added)
    VALUES (p_new_case_id, p_department_id, 'originating', CURDATE());

    INSERT INTO case_investigators (case_id, investigator_id, role_in_case, date_assigned)
    VALUES (p_new_case_id, p_lead_investigator_id, 'lead', CURDATE());

    COMMIT;
END$$

DELIMITER ;

-- ----------------------------------------------------------------------------
-- Procedure 2: sp_assign_investigator
-- Purpose: Adds an investigator to a case in a given role. If assigning a
--          new 'lead', automatically demotes the previous lead to 'support'
--          so a case never silently ends up with two conflicting leads.
-- ----------------------------------------------------------------------------
DELIMITER $$

CREATE PROCEDURE sp_assign_investigator (
    IN p_case_id         INT UNSIGNED,
    IN p_investigator_id INT UNSIGNED,
    IN p_role_in_case    VARCHAR(10)   -- 'lead' or 'support'
)
BEGIN
    DECLARE v_case_exists INT DEFAULT 0;
    DECLARE v_inv_exists  INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT COUNT(*) INTO v_case_exists FROM cases WHERE case_id = p_case_id;
    SELECT COUNT(*) INTO v_inv_exists  FROM investigators WHERE investigator_id = p_investigator_id;

    IF v_case_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sp_assign_investigator: case_id does not exist';
    END IF;

    IF v_inv_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sp_assign_investigator: investigator_id does not exist';
    END IF;

    START TRANSACTION;

    IF p_role_in_case = 'lead' THEN
        UPDATE case_investigators
        SET role_in_case = 'support'
        WHERE case_id = p_case_id AND role_in_case = 'lead';

        UPDATE cases
        SET lead_investigator_id = p_investigator_id
        WHERE case_id = p_case_id;
    END IF;

    INSERT INTO case_investigators (case_id, investigator_id, role_in_case, date_assigned)
    VALUES (p_case_id, p_investigator_id, p_role_in_case, CURDATE())
    ON DUPLICATE KEY UPDATE role_in_case = p_role_in_case;

    COMMIT;
END$$

DELIMITER ;

-- ----------------------------------------------------------------------------
-- Procedure 3: sp_add_digital_evidence
-- Purpose: Intakes a new evidence item, auto-generates its evidence_code,
--          defaults status to 'Collected', and writes the initial
--          chain-of-custody entry (from NULL -> collecting investigator).
-- ----------------------------------------------------------------------------
DELIMITER $$

CREATE PROCEDURE sp_add_digital_evidence (
    IN  p_case_id        INT UNSIGNED,
    IN  p_device_id      INT UNSIGNED,   -- may be NULL
    IN  p_type_id        INT UNSIGNED,
    IN  p_location_id    INT UNSIGNED,
    IN  p_collected_by   INT UNSIGNED,
    IN  p_file_hash      CHAR(64),
    IN  p_file_size      BIGINT UNSIGNED,
    IN  p_description    VARCHAR(255),
    OUT p_new_evidence_id INT UNSIGNED,
    OUT p_evidence_code   VARCHAR(20)
)
BEGIN
    DECLARE v_collected_status_id INT UNSIGNED;
    DECLARE v_next_seq INT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT status_id INTO v_collected_status_id
    FROM evidence_status WHERE status_name = 'Collected' LIMIT 1;

    START TRANSACTION;

    -- Generate a sequential, year-stamped evidence code, e.g. EV-2026-00121
    SELECT COUNT(*) + 1 INTO v_next_seq FROM digital_evidence;
    SET p_evidence_code = CONCAT('EV-', YEAR(CURDATE()), '-', LPAD(v_next_seq, 5, '0'));

    INSERT INTO digital_evidence (
        evidence_code, case_id, device_id, type_id, status_id,
        current_location_id, collected_by, file_hash, file_size_bytes,
        description, date_collected, is_court_submitted
    ) VALUES (
        p_evidence_code, p_case_id, p_device_id, p_type_id, v_collected_status_id,
        p_location_id, p_collected_by, p_file_hash, p_file_size,
        p_description, NOW(), 0
    );

    SET p_new_evidence_id = LAST_INSERT_ID();

    INSERT INTO chain_of_custody (
        evidence_id, from_investigator_id, to_investigator_id,
        from_location_id, to_location_id, transfer_reason, transfer_timestamp, confirmed
    ) VALUES (
        p_new_evidence_id, NULL, p_collected_by,
        NULL, p_location_id, 'Initial collection and intake', NOW(), 1
    );

    COMMIT;
END$$

DELIMITER ;

-- ----------------------------------------------------------------------------
-- Procedure 4: sp_transfer_evidence
-- Purpose: Moves evidence to a new custodian/location as a single atomic
--          operation — writes the custody record AND updates the evidence's
--          current_location_id together, or rolls back entirely on failure.
--          This is the procedure referenced in Phase 12's transaction demo.
-- ----------------------------------------------------------------------------
DELIMITER $$

CREATE PROCEDURE sp_transfer_evidence (
    IN p_evidence_id        INT UNSIGNED,
    IN p_to_investigator_id INT UNSIGNED,
    IN p_to_location_id     INT UNSIGNED,
    IN p_reason             VARCHAR(255)
)
BEGIN
    DECLARE v_current_investigator INT UNSIGNED;
    DECLARE v_current_location     INT UNSIGNED;
    DECLARE v_evidence_exists      INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT COUNT(*) INTO v_evidence_exists
    FROM digital_evidence WHERE evidence_id = p_evidence_id;

    IF v_evidence_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sp_transfer_evidence: evidence_id does not exist';
    END IF;

    START TRANSACTION;

    -- Lock the row for update to avoid a race with a concurrent transfer
    SELECT current_location_id INTO v_current_location
    FROM digital_evidence
    WHERE evidence_id = p_evidence_id
    FOR UPDATE;

    -- Most recent custodian, from the custody log (source of truth)
    SELECT to_investigator_id INTO v_current_investigator
    FROM chain_of_custody
    WHERE evidence_id = p_evidence_id
    ORDER BY transfer_timestamp DESC
    LIMIT 1;

    INSERT INTO chain_of_custody (
        evidence_id, from_investigator_id, to_investigator_id,
        from_location_id, to_location_id, transfer_reason, transfer_timestamp, confirmed
    ) VALUES (
        p_evidence_id, v_current_investigator, p_to_investigator_id,
        v_current_location, p_to_location_id, p_reason, NOW(), 1
    );

    UPDATE digital_evidence
    SET current_location_id = p_to_location_id
    WHERE evidence_id = p_evidence_id;

    COMMIT;
END$$

DELIMITER ;

-- ----------------------------------------------------------------------------
-- Procedure 5: sp_close_case
-- Purpose: Closes a case, but enforces the business rule that a case cannot
--          be closed while it still has evidence in a non-terminal status
--          (i.e., not yet Court-Ready/Archived/Disposed).
-- ----------------------------------------------------------------------------
DELIMITER $$

CREATE PROCEDURE sp_close_case (
    IN p_case_id INT UNSIGNED
)
BEGIN
    DECLARE v_unresolved_evidence INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT COUNT(*) INTO v_unresolved_evidence
    FROM digital_evidence de
    JOIN evidence_status es ON de.status_id = es.status_id
    WHERE de.case_id = p_case_id
      AND es.is_terminal = 0
      AND es.status_name NOT IN ('Court-Ready');

    IF v_unresolved_evidence > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'sp_close_case: case has unresolved evidence not yet Court-Ready/Archived';
    END IF;

    START TRANSACTION;

    UPDATE cases
    SET case_status = 'closed',
        date_closed = CURDATE()
    WHERE case_id = p_case_id;

    COMMIT;
END$$

DELIMITER ;

-- ----------------------------------------------------------------------------
-- Procedure 6: sp_archive_evidence
-- Purpose: Moves an evidence item into the terminal 'Archived' status, but
--          only if its parent case has already been closed — archiving is
--          the end of an evidence item's lifecycle, not a mid-case action.
-- ----------------------------------------------------------------------------
DELIMITER $$

CREATE PROCEDURE sp_archive_evidence (
    IN p_evidence_id INT UNSIGNED
)
BEGIN
    DECLARE v_case_status VARCHAR(30);
    DECLARE v_archived_status_id INT UNSIGNED;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT c.case_status INTO v_case_status
    FROM digital_evidence de
    JOIN cases c ON de.case_id = c.case_id
    WHERE de.evidence_id = p_evidence_id;

    IF v_case_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'sp_archive_evidence: evidence_id does not exist';
    END IF;

    IF v_case_status NOT IN ('closed', 'archived') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'sp_archive_evidence: cannot archive evidence while parent case is still active';
    END IF;

    SELECT status_id INTO v_archived_status_id
    FROM evidence_status WHERE status_name = 'Archived' LIMIT 1;

    START TRANSACTION;

    UPDATE digital_evidence
    SET status_id = v_archived_status_id
    WHERE evidence_id = p_evidence_id;

    COMMIT;
END$$

DELIMITER ;

-- ============================================================================
-- Example calls (for demonstration only — not executed automatically)
-- ============================================================================
-- CALL sp_register_new_case('CC-2026-00099', 'Test Ransomware Case', 'Description here',
--                            1, 5, 'ransomware', 'high', @new_case_id);
-- SELECT @new_case_id;
--
-- CALL sp_assign_investigator(1, 12, 'support');
--
-- CALL sp_add_digital_evidence(1, NULL, 3, 2, 5, SHA2('sample-file-content', 256),
--                               204800, 'Recovered log bundle', @new_ev_id, @new_ev_code);
-- SELECT @new_ev_id, @new_ev_code;
--
-- CALL sp_transfer_evidence(1, 8, 4, 'Transferred for forensic analysis');
--
-- CALL sp_close_case(1);
--
-- CALL sp_archive_evidence(1);

-- ============================================================================
-- END OF PHASE 9 STORED PROCEDURES
-- ============================================================================
