-- ============================================================================
-- Enterprise Digital Evidence Management System (DEMS)
-- Phase 10: Functions (4 functions)
-- MySQL 8.0
-- ============================================================================
USE dems_db;

-- ----------------------------------------------------------------------------
-- Function 1: fn_evidence_count
-- Purpose: Returns the total number of evidence items linked to a given case.
-- Usage:   SELECT fn_evidence_count(1);
-- ----------------------------------------------------------------------------
DELIMITER $$

CREATE FUNCTION fn_evidence_count (p_case_id INT UNSIGNED)
RETURNS INT UNSIGNED
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_count INT UNSIGNED;

    SELECT COUNT(*) INTO v_count
    FROM digital_evidence
    WHERE case_id = p_case_id;

    RETURN v_count;
END$$

DELIMITER ;

-- ----------------------------------------------------------------------------
-- Function 2: fn_case_duration
-- Purpose: Returns the duration of a case in days. For closed/archived
--          cases, that's date_closed - date_opened. For still-open cases,
--          it returns the running duration up to today (useful for spotting
--          cases that have been open unusually long).
-- Usage:   SELECT fn_case_duration(1);
-- ----------------------------------------------------------------------------
DELIMITER $$

CREATE FUNCTION fn_case_duration (p_case_id INT UNSIGNED)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_opened DATE;
    DECLARE v_closed DATE;
    DECLARE v_duration INT;

    SELECT date_opened, date_closed INTO v_opened, v_closed
    FROM cases
    WHERE case_id = p_case_id;

    IF v_opened IS NULL THEN
        RETURN NULL; -- case_id not found
    END IF;

    IF v_closed IS NOT NULL THEN
        SET v_duration = DATEDIFF(v_closed, v_opened);
    ELSE
        SET v_duration = DATEDIFF(CURDATE(), v_opened);
    END IF;

    RETURN v_duration;
END$$

DELIMITER ;

-- ----------------------------------------------------------------------------
-- Function 3: fn_investigator_workload
-- Purpose: Returns the number of currently active (non-closed/archived)
--          cases an investigator is assigned to, across any role.
-- Usage:   SELECT fn_investigator_workload(5);
-- ----------------------------------------------------------------------------
DELIMITER $$

CREATE FUNCTION fn_investigator_workload (p_investigator_id INT UNSIGNED)
RETURNS INT UNSIGNED
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_workload INT UNSIGNED;

    SELECT COUNT(DISTINCT ci.case_id) INTO v_workload
    FROM case_investigators ci
    JOIN cases c ON ci.case_id = c.case_id
    WHERE ci.investigator_id = p_investigator_id
      AND c.case_status NOT IN ('closed', 'archived');

    RETURN v_workload;
END$$

DELIMITER ;

-- ----------------------------------------------------------------------------
-- Function 4: fn_evidence_age
-- Purpose: Returns the number of days since an evidence item was collected —
--          used for aging reports and flagging evidence that has sat too
--          long without progressing through its lifecycle.
-- Usage:   SELECT fn_evidence_age(1);
-- ----------------------------------------------------------------------------
DELIMITER $$

CREATE FUNCTION fn_evidence_age (p_evidence_id INT UNSIGNED)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_collected DATETIME;

    SELECT date_collected INTO v_collected
    FROM digital_evidence
    WHERE evidence_id = p_evidence_id;

    IF v_collected IS NULL THEN
        RETURN NULL; -- evidence_id not found
    END IF;

    RETURN DATEDIFF(CURDATE(), v_collected);
END$$

DELIMITER ;

-- ============================================================================
-- Example usage combining functions with regular queries
-- ============================================================================
-- SELECT case_number, title, fn_evidence_count(case_id) AS evidence_count,
--        fn_case_duration(case_id) AS duration_days
-- FROM cases
-- ORDER BY duration_days DESC;
--
-- SELECT full_name, fn_investigator_workload(investigator_id) AS active_cases
-- FROM investigators
-- ORDER BY active_cases DESC;
--
-- SELECT evidence_code, fn_evidence_age(evidence_id) AS age_in_days
-- FROM digital_evidence
-- WHERE fn_evidence_age(evidence_id) > 180;

-- ============================================================================
-- END OF PHASE 10 FUNCTIONS
-- ============================================================================
