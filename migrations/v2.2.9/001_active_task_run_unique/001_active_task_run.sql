CREATE UNIQUE INDEX IF NOT EXISTS uq_flow_runs_one_active_per_task
    ON flow_runs (task_id)
    WHERE task_id IS NOT NULL
      AND parent_run_id IS NULL
      AND status NOT IN ('completed', 'failed', 'cancelled');

COMMENT ON INDEX uq_flow_runs_one_active_per_task IS
    'A task may have historical retries, but never more than one active root execution.';
