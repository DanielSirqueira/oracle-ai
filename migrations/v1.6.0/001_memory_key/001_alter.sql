-- =====================================================================
-- Memory key: give consolidated memories the same stable-key identity that
-- rules already have, so an agent can UPDATE a memory (supersede by key)
-- instead of piling up near-duplicates.
-- Additive, forward-only. The partial unique indexes only constrain rows
-- WHERE key IS NOT NULL, so existing keyless memories are untouched and the
-- migration cannot fail on an already-populated table.
-- =====================================================================

ALTER TABLE memories ADD COLUMN IF NOT EXISTS key text;

-- One current (is_latest) memory per (owner, key), mirroring the rules indexes.
-- Keyless memories (key IS NULL) are excluded, so they keep the old free-form
-- behavior; only keyed memories get deterministic supersession.
CREATE UNIQUE INDEX IF NOT EXISTS uq_memories_project_key_latest
    ON memories (project_id, key)
    WHERE is_latest AND key IS NOT NULL AND project_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uq_memories_product_key_latest
    ON memories (product_id, key)
    WHERE is_latest AND key IS NOT NULL AND project_id IS NULL AND product_id IS NOT NULL;
