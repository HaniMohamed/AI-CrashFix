-- Temporary status recomputation script.
--
-- Goal: normalize `crashes.status` to only:
--   - in_progress: graph has not ended yet (or no end marker)
--   - completed: required pipeline steps completed (ignoring Jira)
--   - failed: graph ended without completing, or has graph_error, or fix validation failed
--
-- This script derives the "real" status from persisted columns + the stored `result` JSON.
--
-- Usage:
--   sqlite3 db/taminaty-2e06a_crash_store.db < scripts/tmp_recompute_pipeline_status.sql
--   sqlite3 db/<your>_crash_store.db < scripts/tmp_recompute_pipeline_status.sql

.bail on
.echo on

-- Pre-flight: show existing status distribution
SELECT status, COUNT(*) AS n
FROM crashes
GROUP BY status
ORDER BY n DESC;

-- Preview: compute derived status without writing
WITH derived AS (
  SELECT
    crash_id,
    status AS old_status,
    analysis_done, jira_created, fix_generated, fix_validated, diff_applied, branch_created, mr_created,
    CASE
      WHEN (analysis_done AND fix_generated AND fix_validated AND diff_applied AND branch_created AND mr_created) THEN 'completed'
      WHEN COALESCE(NULLIF(json_extract(result, '$.graph_error'), ''), NULL) IS NOT NULL THEN 'failed'
      WHEN COALESCE(json_extract(result, '$.fix_validation_result'), 1) = 0 THEN 'failed'
      -- If the run has an end timestamp but didn't reach completion, it ended unsuccessfully.
      WHEN COALESCE(NULLIF(json_extract(result, '$.graph_run_end_time'), ''), NULL) IS NOT NULL THEN 'failed'
      ELSE 'in_progress'
    END AS new_status
  FROM crashes
)
SELECT old_status, new_status, COUNT(*) AS n
FROM derived
GROUP BY old_status, new_status
ORDER BY n DESC;

-- Write: recompute pipeline_complete and status
UPDATE crashes
SET
  pipeline_complete = CASE
    WHEN (analysis_done AND fix_generated AND fix_validated AND diff_applied AND branch_created AND mr_created) THEN 1
    ELSE 0
  END,
  status = CASE
    WHEN (analysis_done AND fix_generated AND fix_validated AND diff_applied AND branch_created AND mr_created) THEN 'completed'
    WHEN COALESCE(NULLIF(json_extract(result, '$.graph_error'), ''), NULL) IS NOT NULL THEN 'failed'
    WHEN COALESCE(json_extract(result, '$.fix_validation_result'), 1) = 0 THEN 'failed'
    WHEN COALESCE(NULLIF(json_extract(result, '$.graph_run_end_time'), ''), NULL) IS NOT NULL THEN 'failed'
    ELSE 'in_progress'
  END
;

-- Post-flight: show new status distribution
SELECT status, COUNT(*) AS n
FROM crashes
GROUP BY status
ORDER BY n DESC;

