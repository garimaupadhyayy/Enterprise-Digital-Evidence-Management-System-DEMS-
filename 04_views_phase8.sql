-- ============================================================================
-- Enterprise Digital Evidence Management System (DEMS)
-- Phase 8: Views (7 views)
-- MySQL 8.0
-- ============================================================================
USE dems_db;

-- ----------------------------------------------------------------------------
-- View 1: vw_active_cases
-- Purpose: Quick operational dashboard of all cases not yet closed/archived,
--          with lead investigator and department for at-a-glance triage.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_active_cases AS
SELECT
    c.case_id,
    c.case_number,
    c.title,
    c.case_type,
    c.priority,
    c.case_status,
    d.department_name AS originating_department,
    i.full_name        AS lead_investigator,
    c.date_opened,
    DATEDIFF(CURDATE(), c.date_opened) AS days_open
FROM cases c
JOIN departments d    ON c.originating_department_id = d.department_id
JOIN investigators i  ON c.lead_investigator_id = i.investigator_id
WHERE c.case_status NOT IN ('closed', 'archived');

-- ----------------------------------------------------------------------------
-- View 2: vw_evidence_pending_analysis
-- Purpose: Evidence still awaiting or undergoing forensic analysis — the
--          working queue for lab investigators.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_evidence_pending_analysis AS
SELECT
    de.evidence_id,
    de.evidence_code,
    c.case_number,
    et.type_name,
    es.status_name,
    i.full_name AS collected_by,
    sl.location_name,
    de.date_collected,
    DATEDIFF(CURDATE(), de.date_collected) AS days_in_queue
FROM digital_evidence de
JOIN cases c              ON de.case_id = c.case_id
JOIN evidence_types et    ON de.type_id = et.type_id
JOIN evidence_status es   ON de.status_id = es.status_id
JOIN investigators i      ON de.collected_by = i.investigator_id
JOIN storage_locations sl ON de.current_location_id = sl.location_id
WHERE es.status_name IN ('Collected', 'Under Analysis');

-- ----------------------------------------------------------------------------
-- View 3: vw_court_ready_evidence
-- Purpose: Evidence formally marked court-submitted or in Court-Ready status —
--          used by the Legal Division to prepare case files.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_court_ready_evidence AS
SELECT
    de.evidence_id,
    de.evidence_code,
    c.case_number,
    c.title AS case_title,
    es.status_name,
    de.is_court_submitted,
    i.full_name AS collected_by,
    de.date_collected
FROM digital_evidence de
JOIN cases c            ON de.case_id = c.case_id
JOIN evidence_status es ON de.status_id = es.status_id
JOIN investigators i    ON de.collected_by = i.investigator_id
WHERE es.status_name = 'Court-Ready' OR de.is_court_submitted = 1;

-- ----------------------------------------------------------------------------
-- View 4: vw_investigator_workload
-- Purpose: Current caseload and evidence load per investigator — feeds
--          supervisor staffing/reassignment decisions.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_investigator_workload AS
SELECT
    i.investigator_id,
    i.full_name,
    d.department_name,
    COUNT(DISTINCT ci.case_id)  AS active_case_count,
    COUNT(DISTINCT de.evidence_id) AS evidence_collected_count
FROM investigators i
JOIN departments d ON i.department_id = d.department_id
LEFT JOIN case_investigators ci
       ON ci.investigator_id = i.investigator_id
LEFT JOIN cases cs
       ON cs.case_id = ci.case_id AND cs.case_status NOT IN ('closed', 'archived')
LEFT JOIN digital_evidence de
       ON de.collected_by = i.investigator_id
GROUP BY i.investigator_id, i.full_name, d.department_name;

-- ----------------------------------------------------------------------------
-- View 5: vw_daily_evidence_access
-- Purpose: Per-day rollup of evidence access events — supports anomaly
--          detection (e.g., unusual spikes in access volume).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_daily_evidence_access AS
SELECT
    DATE(access_timestamp) AS access_date,
    access_type,
    COUNT(*) AS access_count,
    COUNT(DISTINCT user_id) AS distinct_users,
    COUNT(DISTINCT evidence_id) AS distinct_evidence_items
FROM evidence_access_logs
GROUP BY DATE(access_timestamp), access_type
ORDER BY access_date DESC;

-- ----------------------------------------------------------------------------
-- View 6: vw_monthly_case_summary
-- Purpose: Month-over-month case volume and closure metrics for
--          management reporting.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_monthly_case_summary AS
SELECT
    DATE_FORMAT(date_opened, '%Y-%m') AS month_opened,
    COUNT(*) AS cases_opened,
    SUM(CASE WHEN case_status = 'closed'   THEN 1 ELSE 0 END) AS cases_closed,
    SUM(CASE WHEN case_status = 'archived' THEN 1 ELSE 0 END) AS cases_archived,
    SUM(CASE WHEN priority = 'critical'    THEN 1 ELSE 0 END) AS critical_cases
FROM cases
GROUP BY DATE_FORMAT(date_opened, '%Y-%m')
ORDER BY month_opened;

-- ----------------------------------------------------------------------------
-- View 7 (bonus): vw_chain_of_custody_summary
-- Purpose: Per-evidence custody event count and most recent custodian —
--          quick legal-defensibility check ("is the chain intact/current?").
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_chain_of_custody_summary AS
SELECT
    de.evidence_id,
    de.evidence_code,
    COUNT(co.custody_id) AS total_custody_events,
    MAX(co.transfer_timestamp) AS last_transfer_at,
    SUM(CASE WHEN co.confirmed = 0 THEN 1 ELSE 0 END) AS unconfirmed_transfers
FROM digital_evidence de
LEFT JOIN chain_of_custody co ON co.evidence_id = de.evidence_id
GROUP BY de.evidence_id, de.evidence_code;

-- ============================================================================
-- Sample usage (not part of the view definitions — for demonstration only)
-- ============================================================================
-- SELECT * FROM vw_active_cases ORDER BY days_open DESC;
-- SELECT * FROM vw_investigator_workload ORDER BY active_case_count DESC;
-- SELECT * FROM vw_chain_of_custody_summary WHERE unconfirmed_transfers > 0;

-- ============================================================================
-- END OF PHASE 8 VIEWS
-- ============================================================================
