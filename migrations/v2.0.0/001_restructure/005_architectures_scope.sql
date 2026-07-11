-- =====================================================================
-- v2.0.0 — Restructure (5/8): architecture scoping (organization / project / module).
-- Architecture was project-only (project_id NOT NULL, unique by (project_id, area)).
-- It becomes 3-level like rules/memories: an `area` page can live at the
-- organization, the project, or a module. project_id becomes nullable.
-- =====================================================================

ALTER TABLE architectures ADD COLUMN IF NOT EXISTS organization_id uuid
    REFERENCES organizations(id) ON DELETE CASCADE;
ALTER TABLE architectures ADD COLUMN IF NOT EXISTS module_id uuid
    REFERENCES modules(id) ON DELETE CASCADE;
ALTER TABLE architectures ALTER COLUMN project_id DROP NOT NULL;

ALTER TABLE architectures ADD CONSTRAINT architectures_owner_check
    CHECK (organization_id IS NOT NULL OR project_id IS NOT NULL OR module_id IS NOT NULL);

-- One current page per (owner, area), most specific level wins.
DROP INDEX IF EXISTS uq_architectures_latest;
CREATE UNIQUE INDEX uq_architectures_module_latest
    ON architectures (module_id, area) WHERE is_latest AND module_id IS NOT NULL;
CREATE UNIQUE INDEX uq_architectures_project_latest
    ON architectures (project_id, area)
    WHERE is_latest AND module_id IS NULL AND project_id IS NOT NULL;
CREATE UNIQUE INDEX uq_architectures_organization_latest
    ON architectures (organization_id, area)
    WHERE is_latest AND module_id IS NULL AND project_id IS NULL AND organization_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_architectures_project ON architectures (project_id);
CREATE INDEX IF NOT EXISTS idx_architectures_module ON architectures (module_id);
