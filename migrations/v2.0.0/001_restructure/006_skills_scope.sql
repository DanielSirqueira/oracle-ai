-- =====================================================================
-- v2.0.0 — Restructure (6/8): skills scoping (organization / project / module / global).
-- Skills already supported project / product / GLOBAL (both null). product_id
-- becomes organization_id and a module level is added. Global (all owners null)
-- stays the common case for reusable know-how.
-- =====================================================================

ALTER TABLE skills RENAME COLUMN product_id TO organization_id;
ALTER TABLE skills ADD COLUMN IF NOT EXISTS module_id uuid REFERENCES modules(id) ON DELETE CASCADE;

DROP INDEX IF EXISTS uq_skills_project_key_latest;
DROP INDEX IF EXISTS uq_skills_product_key_latest;
DROP INDEX IF EXISTS uq_skills_global_key_latest;
CREATE UNIQUE INDEX uq_skills_module_key_latest
    ON skills (module_id, key) WHERE is_latest AND module_id IS NOT NULL;
CREATE UNIQUE INDEX uq_skills_project_key_latest
    ON skills (project_id, key)
    WHERE is_latest AND module_id IS NULL AND project_id IS NOT NULL;
CREATE UNIQUE INDEX uq_skills_organization_key_latest
    ON skills (organization_id, key)
    WHERE is_latest AND module_id IS NULL AND project_id IS NULL AND organization_id IS NOT NULL;
CREATE UNIQUE INDEX uq_skills_global_key_latest
    ON skills (key)
    WHERE is_latest AND module_id IS NULL AND project_id IS NULL AND organization_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_skills_module ON skills (module_id);
