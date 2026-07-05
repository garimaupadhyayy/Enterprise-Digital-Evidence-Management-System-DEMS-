-- ============================================================================
-- Enterprise Digital Evidence Management System (DEMS)
-- Phase 12: Transactions (COMMIT / ROLLBACK demonstrations)
-- MySQL 8.0
-- ============================================================================
USE dems_db;

-- ============================================================================
-- Example 1: Successful evidence transfer (manual transaction, no procedure)
-- Demonstrates the two writes that MUST happen together: the custody log
-- entry and the evidence's current_location_id update. Note: because
-- trg_sync_location_after_custody (Phase 11) already propagates the location
-- automatically on INSERT, the explicit UPDATE below is technically
-- redundant in this schema — it's included here deliberately so the
-- transaction's atomicity is visible without relying on trigger behavior,
-- which is the right way to demonstrate transactions in isolation.
-- ============================================================================
START TRANSACTION;

INSERT INTO chain_of_custody (
    evidence_id, from_investigator_id, to_investigator_id,
    from_location_id, to_location_id, transfer_reason, transfer_timestamp, confirmed
) VALUES (
    1, 5, 8, 2, 4, 'Transferred for forensic analysis', NOW(), 1
);

UPDATE digital_evidence
SET current_location_id = 4
WHERE evidence_id = 1;

-- Both writes succeeded — commit them together
COMMIT;


-- ============================================================================
-- Example 2: Failed transfer that must roll back completely
-- Simulates a transfer to a storage_location_id that does not exist. The
-- custody INSERT would succeed on its own if run outside a transaction,
-- leaving a "phantom" custody record with no matching evidence location
-- update — precisely the kind of half-applied write that breaks chain of
-- custody integrity. Wrapping both statements in a transaction guarantees
-- that if the second statement fails, the first is undone too.
-- ============================================================================
START TRANSACTION;

INSERT INTO chain_of_custody (
    evidence_id, from_investigator_id, to_investigator_id,
    from_location_id, to_location_id, transfer_reason, transfer_timestamp, confirmed
) VALUES (
    2, 6, 9, 3, 999, 'Transferred to archive facility', NOW(), 1
);
-- location_id 999 does not exist in storage_locations -> the next statement
-- will fail the FK constraint on current_location_id

-- This UPDATE will raise error 1452 (foreign key constraint fails)
-- because storage_locations.location_id = 999 does not exist:
UPDATE digital_evidence
SET current_location_id = 999
WHERE evidence_id = 2;

-- Because of the FK violation above, roll back everything, including the
-- INSERT into chain_of_custody that DID succeed on its own:
ROLLBACK;

-- Verify the rollback worked — this should return 0 rows for evidence_id = 2
-- with to_location_id = 999:
-- SELECT * FROM chain_of_custody WHERE evidence_id = 2 AND to_location_id = 999;


-- ============================================================================
-- Example 3: Using the stored procedure inside an explicit transaction
-- Procedures already wrap their own internal START TRANSACTION/COMMIT
-- (Phase 9), but they can still be called within an outer transaction if
-- you need to combine a transfer with another related write atomically —
-- e.g., transferring evidence AND logging a manual note in the same
-- all-or-nothing unit of work.
-- ============================================================================
START TRANSACTION;

CALL sp_transfer_evidence(3, 10, 5, 'Transferred to Financial Fraud Unit for joint analysis');

INSERT INTO audit_logs (table_name, record_id, action_type, old_value, new_value, changed_by, changed_at)
VALUES ('digital_evidence', 3, 'UPDATE',
        JSON_OBJECT('note', 'manual transfer annotation'),
        JSON_OBJECT('note', 'transferred per joint investigation request'),
        1, NOW());

COMMIT;


-- ============================================================================
-- Example 4: SAVEPOINT usage — partial rollback within a larger transaction
-- Useful when a batch operation has one step that might fail but you don't
-- want to lose the earlier, valid steps in the same transaction.
-- ============================================================================
START TRANSACTION;

INSERT INTO evidence_access_logs (evidence_id, user_id, access_type, access_timestamp, ip_address)
VALUES (1, 2, 'view', NOW(), '10.0.0.15');

SAVEPOINT after_first_log;

-- Suppose this second log entry references a user_id that does not exist:
-- INSERT INTO evidence_access_logs (evidence_id, user_id, access_type, access_timestamp, ip_address)
-- VALUES (1, 9999, 'view', NOW(), '10.0.0.16');
-- If it fails, roll back only to the savepoint, keeping the first insert:
-- ROLLBACK TO SAVEPOINT after_first_log;

COMMIT;

-- ============================================================================
-- END OF PHASE 12 TRANSACTIONS
-- ============================================================================
