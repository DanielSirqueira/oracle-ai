ALTER TABLE flow_run_steps
    ADD COLUMN IF NOT EXISTS agent_session_id text;

COMMENT ON COLUMN flow_run_steps.agent_session_id IS
    'Native conversation id from the agent CLI (Claude session, Codex thread, Gemini/Cursor session). Reused by later iterations of the same run step definition.';

CREATE INDEX IF NOT EXISTS idx_flow_run_steps_agent_session
    ON flow_run_steps (run_id, step_id, iteration DESC)
    WHERE agent_session_id IS NOT NULL;
