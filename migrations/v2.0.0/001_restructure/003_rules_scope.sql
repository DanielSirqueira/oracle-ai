-- =====================================================================
-- v2.0.0 — Restructure (3/8): rules scoping (organization / project / module).
-- product_id -> organization_id, add module_id. A rule anchors at exactly one
-- level; recall for a module unions module + project + organization, most
-- specific first. The partial unique indexes make each level exclude the more
-- specific ones so "one current version per (owner, key)" holds per level.
-- =====================================================================

ALTER TABLE rules RENAME COLUMN product_id TO organization_id;
ALTER TABLE rules ADD COLUMN IF NOT EXISTS module_id uuid REFERENCES modules(id) ON DELETE CASCADE;

-- Owner check: was (product_id OR project_id); now also allow module-level.
-- Drop the existing owner check by definition (robust to its auto-generated name).
DO $$
DECLARE c text;
BEGIN
  SELECT conname INTO c FROM pg_constraint
   WHERE conrelid = 'rules'::regclass AND contype = 'c'
     AND pg_get_constraintdef(oid) ILIKE '%project_id%'
     AND pg_get_constraintdef(oid) ILIKE '%IS NOT NULL%';
  IF c IS NOT NULL THEN EXECUTE format('ALTER TABLE rules DROP CONSTRAINT %I', c); END IF;
END $$;
ALTER TABLE rules ADD CONSTRAINT rules_owner_check
    CHECK (organization_id IS NOT NULL OR project_id IS NOT NULL OR module_id IS NOT NULL);

-- Per-level current-version uniqueness (most specific level wins).
DROP INDEX IF EXISTS uq_rules_project_latest;
DROP INDEX IF EXISTS uq_rules_product_latest;
CREATE UNIQUE INDEX uq_rules_module_latest
    ON rules (module_id, key) WHERE is_latest AND module_id IS NOT NULL;
CREATE UNIQUE INDEX uq_rules_project_latest
    ON rules (project_id, key)
    WHERE is_latest AND module_id IS NULL AND project_id IS NOT NULL;
CREATE UNIQUE INDEX uq_rules_organization_latest
    ON rules (organization_id, key)
    WHERE is_latest AND module_id IS NULL AND project_id IS NULL AND organization_id IS NOT NULL;

-- FK lookup indexes.
ALTER INDEX idx_rules_product RENAME TO idx_rules_organization;
CREATE INDEX IF NOT EXISTS idx_rules_module ON rules (module_id);
