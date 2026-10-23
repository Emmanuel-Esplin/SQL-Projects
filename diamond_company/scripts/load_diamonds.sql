-- ========================================================================
-- Load the GIA-standard diamond CSV into DIAMONDS
-- ========================================================================
-- Prerequisites:
--   1. python3 scripts/transform_to_gia.py   (creates data/processed/...)
--   2. Server allows local loads:  SET GLOBAL local_infile = 1;
--
-- Run from the diamond_company/ directory (the CSV path is relative to it):
--   mysql --local-infile=1 -u <user> -p Diamond_company < scripts/load_diamonds.sql
-- ========================================================================

USE Diamond_company;

TRUNCATE TABLE stg_diamonds_import;

LOAD DATA LOCAL INFILE 'data/processed/diamonds_prices_2022_gia.csv'
INTO TABLE stg_diamonds_import
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

CALL sp_import_diamonds(@imported, @rejected, @err);

SELECT @imported AS imported, @rejected AS rejected, NULLIF(@err, '') AS error;
