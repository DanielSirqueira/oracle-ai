-- =====================================================================
-- v2.0.0 — Restructure (1/8): products -> organizations.
-- An organization (e.g. a company) groups many projects. This renames the
-- table and the projects FK column in place; all data is preserved. FK and
-- unique-constraint objects follow the rename automatically (only their names
-- keep the old spelling, which is cosmetic).
-- =====================================================================

ALTER TABLE products RENAME TO organizations;

ALTER TABLE projects RENAME COLUMN product_id TO organization_id;
ALTER INDEX idx_projects_product RENAME TO idx_projects_organization;
