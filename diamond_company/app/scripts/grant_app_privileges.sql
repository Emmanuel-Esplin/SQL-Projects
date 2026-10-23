-- ========================================================================
-- Least-privilege MySQL account for the web app
-- ========================================================================
-- 1. Create the account yourself, choosing a strong password, e.g.:
--      mysql -u root -p -e "CREATE USER 'diamond_app'@'localhost' IDENTIFIED BY '<your password>';"
--    (Never commit that password. Put it only in app/.env as DT_DB_PASSWORD.)
-- 2. Then grant its privileges:
--      mysql -u root -p < scripts/grant_app_privileges.sql
--
-- The app can read data, insert/update rows and run the procedures. It
-- cannot DELETE, DROP, ALTER or create objects. Procedures run with their
-- definer's rights, so all state changes still pass their checks.
-- ========================================================================

GRANT SELECT, INSERT, UPDATE, EXECUTE ON Diamond_company.* TO 'diamond_app'@'localhost';
