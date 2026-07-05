# Phase 15 — Testing Scenarios

Each scenario below tests a specific piece of enforced logic (constraint, trigger, or procedure business rule) rather than just "does SELECT work." Run these against the loaded database (Phases 5–6) in order.

---

### Test 1 — Referential integrity: reject an evidence insert with an invalid case_id
```sql
INSERT INTO digital_evidence (evidence_code, case_id, type_id, status_id, current_location_id, collected_by, file_hash, file_size_bytes)
VALUES ('EV-2026-99999', 99999, 1, 1, 1, 1, SHA2('test', 256), 1000);
```
**Expected output:** `ERROR 1452 (23000): Cannot add or update a child row: a foreign key constraint fails` — `case_id 99999` doesn't exist in `cases`.

---

### Test 2 — CHECK constraint: reject a case where date_closed precedes date_opened
```sql
INSERT INTO cases (case_number, title, originating_department_id, lead_investigator_id, date_opened, date_closed)
VALUES ('CC-2026-TEST1', 'Test Case', 1, 1, '2026-06-01', '2026-05-01');
```
**Expected output:** `ERROR 3819 (HY000): Check constraint 'chk_case_dates' is violated.`

---

### Test 3 — Trigger: prevent deleting evidence linked to an active case
```sql
-- Pick any evidence_id whose case is still 'open' or 'under_investigation'
DELETE FROM digital_evidence WHERE evidence_id = 1;
```
**Expected output:** `ERROR 1644 (45000): Cannot delete evidence linked to an active case. Close the case first.`
**Follow-up:** Close the parent case first (`CALL sp_close_case(<case_id>)` — after resolving its evidence), then retry the DELETE. It should now succeed if the case is `closed`/`archived`.

---

### Test 4 — Trigger: block a backward evidence status transition
```sql
-- Find an evidence_id currently at status 'Analyzed' (status_order 3) and try to move it back to 'Collected' (status_order 1)
UPDATE digital_evidence SET status_id = 1 WHERE evidence_id = <analyzed_evidence_id>;
```
**Expected output:** `ERROR 1644 (45000): Invalid status transition: evidence status cannot move backward.`

---

### Test 5 — Trigger: automatic audit log on case update
```sql
SET @app_user_id = 3;
UPDATE cases SET priority = 'critical' WHERE case_id = 1;
SELECT * FROM audit_logs WHERE table_name = 'cases' AND record_id = 1 ORDER BY audit_id DESC LIMIT 1;
```
**Expected output:** A new row in `audit_logs` with `action_type = 'UPDATE'`, `changed_by = 3`, and `new_value` containing `"priority": "critical"`.

---

### Test 6 — Trigger: chain of custody insert auto-syncs evidence location
```sql
INSERT INTO chain_of_custody (evidence_id, from_investigator_id, to_investigator_id, from_location_id, to_location_id, transfer_reason, confirmed)
VALUES (5, 2, 7, 1, 6, 'Test transfer', 1);
SELECT current_location_id FROM digital_evidence WHERE evidence_id = 5;
```
**Expected output:** `current_location_id` for evidence 5 is now `6`, matching the custody record's `to_location_id`, without any separate manual UPDATE statement.

---

### Test 7 — Procedure: sp_register_new_case rejects an invalid department
```sql
CALL sp_register_new_case('CC-2026-TEST2', 'Bad Department Test', 'desc', 9999, 1, 'fraud', 'medium', @new_id);
```
**Expected output:** `ERROR 1644 (45000): sp_register_new_case: department_id does not exist` — no case row is created (transaction rolled back before any INSERT).

---

### Test 8 — Procedure: sp_close_case blocks closure with unresolved evidence
```sql
-- Pick a case_id that has evidence still in 'Collected' or 'Under Analysis'
CALL sp_close_case(<case_id_with_pending_evidence>);
```
**Expected output:** `ERROR 1644 (45000): sp_close_case: case has unresolved evidence not yet Court-Ready/Archived`

---

### Test 9 — Procedure: sp_transfer_evidence full happy-path
```sql
CALL sp_transfer_evidence(10, 4, 3, 'Test transfer to specialist');
SELECT * FROM chain_of_custody WHERE evidence_id = 10 ORDER BY custody_id DESC LIMIT 1;
SELECT current_location_id FROM digital_evidence WHERE evidence_id = 10;
```
**Expected output:** A new `chain_of_custody` row with `to_investigator_id = 4`, `to_location_id = 3`; `digital_evidence.current_location_id` for evidence 10 is now `3`.

---

### Test 10 — Function: fn_case_duration for an open vs. closed case
```sql
SELECT case_id, case_status, fn_case_duration(case_id) AS duration_days
FROM cases
WHERE case_id IN (<an_open_case_id>, <a_closed_case_id>);
```
**Expected output:** For the open case, `duration_days` equals `DATEDIFF(CURDATE(), date_opened)` (a running count that increases daily). For the closed case, it equals the fixed `DATEDIFF(date_closed, date_opened)` and won't change on subsequent days.

---

### Test 11 — View: vw_evidence_pending_analysis excludes resolved evidence
```sql
SELECT COUNT(*) FROM vw_evidence_pending_analysis WHERE evidence_id IN (
    SELECT evidence_id FROM digital_evidence de
    JOIN evidence_status es ON de.status_id = es.status_id
    WHERE es.status_name IN ('Court-Ready','Archived','Disposed')
);
```
**Expected output:** `0` — the view's `WHERE es.status_name IN ('Collected','Under Analysis')` filter should never include terminal-stage evidence.

---

### Test 12 — Transaction rollback integrity (Phase 12, Example 2 pattern)
```sql
START TRANSACTION;
INSERT INTO chain_of_custody (evidence_id, from_investigator_id, to_investigator_id, from_location_id, to_location_id, transfer_reason, confirmed)
VALUES (7, 1, 2, 1, 999, 'Test bad transfer', 1);
-- location_id 999 doesn't exist, so this fails the FK constraint on chain_of_custody itself:
```
**Expected output:** The INSERT itself fails immediately with `ERROR 1452` (FK violation on `to_location_id`), since `chain_of_custody.to_location_id` has an FK to `storage_locations`. A subsequent `SELECT * FROM chain_of_custody WHERE evidence_id = 7 AND to_location_id = 999;` returns 0 rows, confirming nothing was partially written.

---

### Test 13 — Security: least-privilege enforcement
```sql
-- Connect as dems_investigator (Phase 14) and attempt a direct UPDATE
-- that bypasses the stored procedures:
UPDATE digital_evidence SET status_id = 6 WHERE evidence_id = 1;
```
**Expected output:** `ERROR 1142 (42000): UPDATE command denied to user 'dems_investigator'@'localhost' for table 'digital_evidence'` — confirming the role has no direct write grant and must use `sp_transfer_evidence`/`sp_archive_evidence` instead.

---

## Test Execution Summary Template

| # | Scenario | Expected Result | Pass/Fail |
|---|---|---|---|
| 1 | Invalid case_id FK | ERROR 1452 | |
| 2 | date_closed < date_opened | ERROR 3819 | |
| 3 | Delete evidence on active case | ERROR 1644 | |
| 4 | Backward status transition | ERROR 1644 | |
| 5 | Audit log on case update | New audit_logs row | |
| 6 | Custody insert syncs location | current_location_id updated | |
| 7 | Invalid department in new case | ERROR 1644, no case created | |
| 8 | Close case with pending evidence | ERROR 1644 | |
| 9 | Transfer evidence happy path | Custody + location updated | |
| 10 | Case duration function | Correct day counts | |
| 11 | Pending-analysis view filter | 0 resolved items shown | |
| 12 | Transaction rollback on bad FK | 0 partial rows persisted | |
| 13 | Least-privilege direct UPDATE | ERROR 1142 | |

Fill in Pass/Fail once run against your local MySQL instance — I don't have a live MySQL server in this environment to execute these myself, so this table is meant to be your actual test log for the submission.
