# Phase 13 — Indexing Strategy

All indexes below were already created in `01_schema_phase5.sql`. This document explains the reasoning behind each one — the kind of justification an interviewer or code reviewer would expect, rather than just "add an index and hope."

## Indexes MySQL creates automatically (not listed again below)
Every `PRIMARY KEY`, `UNIQUE` constraint, and `FOREIGN KEY` column already gets an index automatically in InnoDB. That covers most single-column lookups (`case_id`, `evidence_id`, `user_id`, all the `*_code`/`*_number` uniques, etc.) without any extra work. The indexes below are the **additional** ones added deliberately for query patterns that the automatic indexes don't fully serve.

---

## 1. `idx_cases_status` on `cases(case_status)`
**Why:** `case_status` is filtered constantly — the entire `vw_active_cases` view, `sp_close_case`, and most case dashboards filter `WHERE case_status NOT IN ('closed','archived')` or similar. Without this index, every such query does a full table scan of `cases`. With low cardinality (5 possible values) this index is less selective than an ID lookup, but it's still a clear win once the `cases` table grows past a few thousand rows, and it costs almost nothing to maintain.

## 2. `idx_cases_priority` on `cases(priority)`
**Why:** Priority-based triage ("show me all critical cases") is a core dashboard query. Same low-cardinality trade-off as above — still worth it once volume grows.

## 3. `idx_cases_dates` on `cases(date_opened, date_closed)`
**Why:** Supports the monthly/duration reporting queries (Phase 7 Q29–Q30, `vw_monthly_case_summary`) that filter and group by date ranges. A composite index here lets MySQL range-scan by `date_opened` and still have `date_closed` available without a second lookup for duration calculations.

## 4. `idx_evidence_case` on `digital_evidence(case_id)`
**Why:** Technically this column already has an FK-backed index, but it's called out explicitly here because it's the single most frequently joined column in the entire schema — nearly every evidence report joins `digital_evidence` to `cases`. Confirming this index exists (rather than assuming the FK index covers the access pattern well) is worth stating explicitly in a design doc.

## 5. `idx_evidence_status` on `digital_evidence(status_id)`
**Why:** `vw_evidence_pending_analysis` and `vw_court_ready_evidence` both filter heavily by status. Evidence status has more cardinality than case status (7 values) so this index is more selective and pays for itself sooner.

## 6. `idx_evidence_collected` on `digital_evidence(date_collected)`
**Why:** Supports evidence-aging reports (`fn_evidence_age`, Q28's age-bucket query) and any "evidence collected in the last N days" filter — a very common operational question in a forensics unit.

## 7. `idx_custody_evidence` on `chain_of_custody(evidence_id, transfer_timestamp)`
**Why:** This is the most performance-critical index in the whole system. Every "show me the full custody history for this evidence item, in order" query — which is the literal legal purpose of this table — needs to filter by `evidence_id` and sort by `transfer_timestamp`. A composite index in that exact order lets MySQL satisfy both the filter and the `ORDER BY` from the index alone, without a separate filesort step. This also directly speeds up `trg_sync_location_after_custody` and the "latest custody per evidence" window-function query (Q24).

## 8. `idx_accesslog_evidence` on `evidence_access_logs(evidence_id, access_timestamp)`
**Why:** Same reasoning as #7 — "who has accessed this evidence, and when" is a security-review query that needs both filter and chronological order.

## 9. `idx_accesslog_user` on `evidence_access_logs(user_id, access_timestamp)`
**Why:** The complementary access pattern — "what has this user accessed, and when" — used for insider-threat/anomaly detection (e.g., a user viewing an unusual volume of evidence overnight).

## 10. `idx_audit_table_record` on `audit_logs(table_name, record_id)`
**Why:** Audit review is almost always "show me the full change history for this specific case/evidence row," which means filtering by both `table_name` and `record_id` together — a composite index here avoids scanning the (potentially very large) audit table.

## 11. `idx_audit_changed_at` on `audit_logs(changed_at)`
**Why:** Compliance reporting frequently needs "all changes in the last 30 days" style queries independent of which table/record was touched — a time-range scan across the whole audit trail.

## 12. `idx_investigators_dept` on `investigators(department_id)`
**Why:** Department-level rollups (`vw_investigator_workload`, department headcount reports) filter/group by department constantly.

## 13. `idx_devices_suspect` on `devices(suspect_id)`
**Why:** "All devices seized from this suspect" is a standard investigative query, and `suspect_id` is nullable so it isn't automatically the most selective FK index MySQL would prioritize without being told.

---

## Indexes deliberately *not* added
- No index on `suspects.full_name` or `investigators.full_name` — free-text name search would need a `FULLTEXT` index or an external search layer (e.g., Elasticsearch) rather than a plain B-tree index, since partial/fuzzy name matching doesn't benefit from a standard index anyway. Flagged as a future improvement (Phase 16) rather than solved here.
- No index on `digital_evidence.description` or any other free-text/description column — same reasoning; B-tree indexes don't help `LIKE '%...%'` queries.
- No additional index on `evidence_types.category_id` — the table is tiny (22 rows), so a full scan costs nothing; indexing it would be pure overhead for zero benefit.

## General principle applied throughout
Every index above targets a **filter + sort combination that repeats across multiple named queries, views, or procedures in this project** — not a hypothetical. Indexes aren't free: each one adds write overhead (every INSERT/UPDATE has to maintain it) and storage cost, so the rule followed here was "only index what's actually queried repeatedly," rather than indexing every column defensively.
