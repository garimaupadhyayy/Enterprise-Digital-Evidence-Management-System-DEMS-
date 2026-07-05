-- ============================================================================
-- Enterprise Digital Evidence Management System (DEMS)
-- Phase 7: Advanced SQL Queries (36 queries)
-- MySQL 8.0
-- ============================================================================
USE dems_db;

-- ============================================================================
-- SECTION A: SIMPLE SELECT / FILTERING / ORDER BY
-- ============================================================================

-- Q1. Simple SELECT — list all cases with core details
SELECT case_id, case_number, title, case_status, priority, date_opened
FROM cases;

-- Q2. Filtering — evidence currently under analysis
SELECT evidence_id, evidence_code, case_id, file_size_bytes, date_collected
FROM digital_evidence de
JOIN evidence_status es ON de.status_id = es.status_id
WHERE es.status_name = 'Under Analysis';

-- Q3. Filtering with multiple conditions — high/critical priority open cases
SELECT case_number, title, priority, case_status, date_opened
FROM cases
WHERE priority IN ('high', 'critical')
  AND case_status IN ('open', 'under_investigation');

-- Q4. ORDER BY — investigators sorted by department then badge number
SELECT investigator_id, full_name, department_id, badge_number
FROM investigators
ORDER BY department_id ASC, badge_number ASC;

-- Q5. ORDER BY with LIMIT — 10 most recently collected evidence items
SELECT evidence_code, case_id, date_collected
FROM digital_evidence
ORDER BY date_collected DESC
LIMIT 10;

-- ============================================================================
-- SECTION B: GROUP BY / HAVING / AGGREGATES
-- ============================================================================

-- Q6. GROUP BY — number of cases per department
SELECT d.department_name, COUNT(c.case_id) AS total_cases
FROM departments d
LEFT JOIN cases c ON c.originating_department_id = d.department_id
GROUP BY d.department_name
ORDER BY total_cases DESC;

-- Q7. HAVING — departments handling more than 5 originating cases
SELECT d.department_name, COUNT(c.case_id) AS total_cases
FROM departments d
JOIN cases c ON c.originating_department_id = d.department_id
GROUP BY d.department_name
HAVING COUNT(c.case_id) > 5;

-- Q8. Aggregate functions — average, min, max evidence file size by type
SELECT et.type_name,
       ROUND(AVG(de.file_size_bytes), 2) AS avg_size_bytes,
       MIN(de.file_size_bytes)           AS min_size_bytes,
       MAX(de.file_size_bytes)           AS max_size_bytes,
       COUNT(*)                          AS evidence_count
FROM digital_evidence de
JOIN evidence_types et ON de.type_id = et.type_id
GROUP BY et.type_name
ORDER BY evidence_count DESC;

-- Q9. GROUP BY with HAVING on aggregate — investigators who collected more than 3 evidence items
SELECT i.full_name, COUNT(de.evidence_id) AS items_collected
FROM investigators i
JOIN digital_evidence de ON de.collected_by = i.investigator_id
GROUP BY i.full_name
HAVING COUNT(de.evidence_id) > 3
ORDER BY items_collected DESC;

-- ============================================================================
-- SECTION C: JOINS (INNER / LEFT / RIGHT / SELF)
-- ============================================================================

-- Q10. INNER JOIN — evidence with case title and current status
SELECT de.evidence_code, c.title, es.status_name, de.date_collected
FROM digital_evidence de
INNER JOIN cases c ON de.case_id = c.case_id
INNER JOIN evidence_status es ON de.status_id = es.status_id;

-- Q11. LEFT JOIN — all devices with owning suspect (NULL where owner unknown)
SELECT dv.device_id, dv.device_type, dv.serial_number, s.full_name AS suspect_name
FROM devices dv
LEFT JOIN suspects s ON dv.suspect_id = s.suspect_id
ORDER BY suspect_name IS NULL, s.full_name;

-- Q12. LEFT JOIN — departments with head investigator (some may be unassigned)
SELECT d.department_name, i.full_name AS head_investigator
FROM departments d
LEFT JOIN investigators i ON d.head_investigator_id = i.investigator_id;

-- Q13. RIGHT JOIN — storage locations and any evidence stored there (keeps empty locations too)
SELECT sl.location_name, de.evidence_code
FROM digital_evidence de
RIGHT JOIN storage_locations sl ON de.current_location_id = sl.location_id
ORDER BY sl.location_name;

-- Q14. Multi-table JOIN — full evidence dossier (case, type, status, location, collector)
SELECT de.evidence_code, c.case_number, et.type_name, es.status_name,
       sl.location_name, i.full_name AS collected_by_investigator
FROM digital_evidence de
JOIN cases c              ON de.case_id = c.case_id
JOIN evidence_types et     ON de.type_id = et.type_id
JOIN evidence_status es    ON de.status_id = es.status_id
JOIN storage_locations sl  ON de.current_location_id = sl.location_id
JOIN investigators i       ON de.collected_by = i.investigator_id;

-- Q15. SELF JOIN — pairs of investigators working in the same department
SELECT a.full_name AS investigator_a, b.full_name AS investigator_b, a.department_id
FROM investigators a
JOIN investigators b
     ON a.department_id = b.department_id
    AND a.investigator_id < b.investigator_id
ORDER BY a.department_id;

-- Q16. SELF JOIN — chain of custody handoffs (who transferred to whom)
SELECT co.custody_id, fi.full_name AS from_investigator, ti.full_name AS to_investigator,
       co.transfer_timestamp
FROM chain_of_custody co
LEFT JOIN investigators fi ON co.from_investigator_id = fi.investigator_id
JOIN investigators ti       ON co.to_investigator_id = ti.investigator_id
ORDER BY co.transfer_timestamp;

-- ============================================================================
-- SECTION D: SUBQUERIES / CORRELATED SUBQUERIES / CTEs
-- ============================================================================

-- Q17. Subquery — cases with more evidence items than the average case
SELECT case_id, case_number
FROM cases
WHERE case_id IN (
    SELECT case_id FROM digital_evidence
    GROUP BY case_id
    HAVING COUNT(*) > (
        SELECT AVG(cnt) FROM (
            SELECT COUNT(*) AS cnt FROM digital_evidence GROUP BY case_id
        ) AS per_case_counts
    )
);

-- Q18. Correlated subquery — evidence items accessed more times than the average access count for their own evidence
SELECT de.evidence_code,
       (SELECT COUNT(*) FROM evidence_access_logs eal WHERE eal.evidence_id = de.evidence_id) AS access_count
FROM digital_evidence de
WHERE (SELECT COUNT(*) FROM evidence_access_logs eal WHERE eal.evidence_id = de.evidence_id) >
      (SELECT AVG(cnt) FROM (
          SELECT COUNT(*) AS cnt FROM evidence_access_logs GROUP BY evidence_id
      ) AS avg_access);

-- Q19. Correlated subquery — investigators who are the lead on at least one case
SELECT i.full_name
FROM investigators i
WHERE EXISTS (
    SELECT 1 FROM case_investigators ci
    WHERE ci.investigator_id = i.investigator_id AND ci.role_in_case = 'lead'
);

-- Q20. CTE — case summary combining evidence counts and suspect counts
WITH case_evidence AS (
    SELECT case_id, COUNT(*) AS evidence_count
    FROM digital_evidence
    GROUP BY case_id
),
case_suspect_count AS (
    SELECT case_id, COUNT(*) AS suspect_count
    FROM case_suspects
    GROUP BY case_id
)
SELECT c.case_number, c.title, c.case_status,
       COALESCE(ce.evidence_count, 0) AS evidence_count,
       COALESCE(cs.suspect_count, 0) AS suspect_count
FROM cases c
LEFT JOIN case_evidence ce ON c.case_id = ce.case_id
LEFT JOIN case_suspect_count cs ON c.case_id = cs.case_id
ORDER BY evidence_count DESC;

-- Q21. CTE — department workload (cases + evidence rolled up)
WITH dept_cases AS (
    SELECT originating_department_id AS department_id, COUNT(*) AS case_count
    FROM cases
    GROUP BY originating_department_id
),
dept_evidence AS (
    SELECT c.originating_department_id AS department_id, COUNT(de.evidence_id) AS evidence_count
    FROM cases c
    JOIN digital_evidence de ON de.case_id = c.case_id
    GROUP BY c.originating_department_id
)
SELECT d.department_name,
       COALESCE(dc.case_count, 0) AS case_count,
       COALESCE(de_.evidence_count, 0) AS evidence_count
FROM departments d
LEFT JOIN dept_cases dc ON d.department_id = dc.department_id
LEFT JOIN dept_evidence de_ ON d.department_id = de_.department_id
ORDER BY evidence_count DESC;

-- ============================================================================
-- SECTION E: WINDOW FUNCTIONS / RANKING / TOP-N
-- ============================================================================

-- Q22. Window function — RANK investigators by evidence items collected
SELECT i.full_name,
       COUNT(de.evidence_id) AS items_collected,
       RANK() OVER (ORDER BY COUNT(de.evidence_id) DESC) AS workload_rank
FROM investigators i
LEFT JOIN digital_evidence de ON de.collected_by = i.investigator_id
GROUP BY i.investigator_id, i.full_name;

-- Q23. Window function — running total of evidence collected per month
SELECT DATE_FORMAT(date_collected, '%Y-%m') AS month,
       COUNT(*) AS monthly_count,
       SUM(COUNT(*)) OVER (ORDER BY DATE_FORMAT(date_collected, '%Y-%m')) AS running_total
FROM digital_evidence
GROUP BY DATE_FORMAT(date_collected, '%Y-%m')
ORDER BY month;

-- Q24. Window function — ROW_NUMBER to get the most recent custody event per evidence item
SELECT * FROM (
    SELECT co.*, ROW_NUMBER() OVER (PARTITION BY evidence_id ORDER BY transfer_timestamp DESC) AS rn
    FROM chain_of_custody co
) latest_custody
WHERE rn = 1;

-- Q25. Window function — DENSE_RANK departments by total case count
SELECT department_name, total_cases,
       DENSE_RANK() OVER (ORDER BY total_cases DESC) AS dept_rank
FROM (
    SELECT d.department_name, COUNT(c.case_id) AS total_cases
    FROM departments d
    LEFT JOIN cases c ON c.originating_department_id = d.department_id
    GROUP BY d.department_name
) dept_totals;

-- Q26. Top-N report — top 5 cases by evidence volume
SELECT c.case_number, c.title, COUNT(de.evidence_id) AS evidence_count
FROM cases c
JOIN digital_evidence de ON de.case_id = c.case_id
GROUP BY c.case_id, c.case_number, c.title
ORDER BY evidence_count DESC
LIMIT 5;

-- Q27. Top-N report — top 10 most-accessed evidence items
SELECT de.evidence_code, COUNT(eal.access_id) AS access_count
FROM digital_evidence de
JOIN evidence_access_logs eal ON eal.evidence_id = de.evidence_id
GROUP BY de.evidence_id, de.evidence_code
ORDER BY access_count DESC
LIMIT 10;

-- ============================================================================
-- SECTION F: CASE STATEMENTS / DATE FUNCTIONS / STRING FUNCTIONS
-- ============================================================================

-- Q28. CASE statement — bucket evidence by age since collection
SELECT evidence_code, date_collected,
       DATEDIFF(CURDATE(), date_collected) AS days_since_collection,
       CASE
           WHEN DATEDIFF(CURDATE(), date_collected) <= 30 THEN 'Recent'
           WHEN DATEDIFF(CURDATE(), date_collected) <= 180 THEN 'Mid-term'
           ELSE 'Aged'
       END AS age_bucket
FROM digital_evidence
ORDER BY days_since_collection DESC;

-- Q29. Date functions — cases opened per month/year (monthly report)
SELECT YEAR(date_opened) AS yr, MONTH(date_opened) AS mo, COUNT(*) AS cases_opened
FROM cases
GROUP BY YEAR(date_opened), MONTH(date_opened)
ORDER BY yr, mo;

-- Q30. Date functions — average case duration in days for closed/archived cases
SELECT case_status,
       ROUND(AVG(DATEDIFF(date_closed, date_opened)), 1) AS avg_duration_days
FROM cases
WHERE date_closed IS NOT NULL
GROUP BY case_status;

-- Q31. String functions — normalized suspect display name (upper last name, proper case)
SELECT suspect_id,
       CONCAT(full_name, IFNULL(CONCAT(' (alias: ', alias, ')'), '')) AS display_name,
       UPPER(SUBSTRING_INDEX(full_name, ' ', -1)) AS last_name_upper
FROM suspects;

-- Q32. String functions — mask email domain for privacy-conscious reporting
SELECT username,
       CONCAT(LEFT(email, LOCATE('@', email) - 1), '@***') AS masked_email
FROM users;

-- ============================================================================
-- SECTION G: DOMAIN REPORTS (Evidence / Case / Investigator / Storage / Custody / Audit)
-- ============================================================================

-- Q33. Evidence report — evidence count and total size by category
SELECT ec.category_name,
       COUNT(de.evidence_id) AS evidence_count,
       SUM(de.file_size_bytes) AS total_bytes
FROM evidence_categories ec
JOIN evidence_types et ON et.category_id = ec.category_id
JOIN digital_evidence de ON de.type_id = et.type_id
GROUP BY ec.category_name
ORDER BY total_bytes DESC;

-- Q34. Storage report — utilization percentage per location, flag near-capacity
SELECT location_name, capacity, current_utilization,
       ROUND(current_utilization / capacity * 100, 1) AS utilization_pct,
       CASE WHEN current_utilization / capacity > 0.85 THEN 'Near Capacity' ELSE 'OK' END AS capacity_flag
FROM storage_locations
ORDER BY utilization_pct DESC;

-- Q35. Chain of custody report — number of transfers per evidence item, ordered by most-transferred
SELECT de.evidence_code, COUNT(co.custody_id) AS transfer_count
FROM digital_evidence de
JOIN chain_of_custody co ON co.evidence_id = de.evidence_id
GROUP BY de.evidence_id, de.evidence_code
ORDER BY transfer_count DESC;

-- Q36. Audit report — actions logged per user per action type (compliance review)
SELECT u.username, al.action_type, COUNT(*) AS action_count
FROM audit_logs al
JOIN users u ON al.changed_by = u.user_id
GROUP BY u.username, al.action_type
ORDER BY u.username, action_count DESC;

-- ============================================================================
-- END OF PHASE 7 QUERIES
-- ============================================================================
