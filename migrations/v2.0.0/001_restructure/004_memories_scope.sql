-- =====================================================================
-- v2.0.0 — Restructure (4/8): memories scoping (organization / project / module).
-- Same 3-level model as rules. Memory keys are optional, so the keyed unique
-- indexes stay guarded by `key IS NOT NULL` (keyless memories are unconstrained).
-- =====================================================================

ALTER TABLE memories RENAME COLUMN product_id TO organization_id;
ALTER TABLE memories ADD COLUMN IF NOT EXISTS module_id uuid REFERENCES modules(id) ON DELETE CASCADE;

DO $$
DECLARE c text;
BEGIN
  SELECT conname INTO c FROM pg_constraint
   WHERE conrelid = 'memories'::regclass AND contype = 'c'
     AND pg_get_constraintdef(oid) ILIKE '%project_id%'
     AND pg_get_constraintdef(oid) ILIKE '%IS NOT NULL%';
  IF c IS NOT NULL THEN EXECUTE format('ALTER TABLE memories DROP CONSTRAINT %I', c); END IF;
END $$;
ALTER TABLE memories ADD CONSTRAINT memories_owner_check
    CHECK (organization_id IS NOT NULL OR project_id IS NOT NULL OR module_id IS NOT NULL);

DROP INDEX IF EXISTS uq_memories_project_key_latest;
DROP INDEX IF EXISTS uq_memories_product_key_latest;
CREATE UNIQUE INDEX uq_memories_module_key_latest
    ON memories (module_id, key)
    WHERE is_latest AND key IS NOT NULL AND module_id IS NOT NULL;
CREATE UNIQUE INDEX uq_memories_project_key_latest
    ON memories (project_id, key)
    WHERE is_latest AND key IS NOT NULL AND module_id IS NULL AND project_id IS NOT NULL;
CREATE UNIQUE INDEX uq_memories_organization_key_latest
    ON memories (organization_id, key)
    WHERE is_latest AND key IS NOT NULL AND module_id IS NULL AND project_id IS NULL
      AND organization_id IS NOT NULL;

ALTER INDEX idx_memories_product RENAME TO idx_memories_organization;
CREATE INDEX IF NOT EXISTS idx_memories_module ON memories (module_id) WHERE is_latest;
