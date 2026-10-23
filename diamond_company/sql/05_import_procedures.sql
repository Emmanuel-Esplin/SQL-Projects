-- ========================================================================
-- Diamond CSV Import - Staging Table and Procedure
-- ========================================================================
-- MySQL does not allow LOAD DATA inside stored programs, so the import
-- has two steps:
--   1. scripts/load_diamonds.sql runs LOAD DATA LOCAL INFILE on the client
--      into stg_diamonds_import.
--   2. sp_import_diamonds() validates staged rows against the GIA 4Cs
--      reference tables and inserts them into DIAMONDS.
--
-- Staging columns match data/processed/diamonds_prices_2022_gia.csv
-- (produced by scripts/transform_to_gia.py):
-- diamond_id,carat_weight,cut_grade,color_grade,clarity_grade,depth_percent,
-- table_percent,length_mm,width_mm,depth_mm,price_usd,certification_status
-- ========================================================================

USE Diamond_company;

DROP TABLE IF EXISTS stg_diamonds_import;
CREATE TABLE stg_diamonds_import (
  csv_diamond_id VARCHAR(20),
  csv_carat_weight VARCHAR(20),
  csv_cut_grade VARCHAR(20),
  csv_color_grade VARCHAR(5),
  csv_clarity_grade VARCHAR(10),
  csv_depth_percent VARCHAR(20),
  csv_table_percent VARCHAR(20),
  csv_length_mm VARCHAR(20),
  csv_width_mm VARCHAR(20),
  csv_depth_mm VARCHAR(20),
  csv_price_usd VARCHAR(20),
  csv_certification_status VARCHAR(20)
) ENGINE=InnoDB
  COMMENT='Raw CSV rows awaiting validation by sp_import_diamonds';

DROP PROCEDURE IF EXISTS sp_import_diamonds;

DELIMITER $$

-- ========================================================================
-- Import staged rows into DIAMONDS
-- ========================================================================
-- * Grades must exist in CUT, COLOR and CLARITY (GIA scales).
-- * Carat is rounded to the hundredth, as on a GIA report.
-- * base_price_per_carat is derived so sp_compute_price reproduces the
--   CSV price: price / (carat * cut_mult * color_mult * clarity_mult).
-- * Re-runnable: rows whose SKU already exists are skipped.
-- Usage: CALL sp_import_diamonds(@imported, @rejected, @err);
-- ========================================================================
CREATE PROCEDURE sp_import_diamonds(
  OUT p_imported INT,
  OUT p_rejected INT,
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_supplier_id INT;
  DECLARE v_rough_id INT;
  DECLARE v_staged INT;
  DECLARE v_valid INT;
  DECLARE v_total_carat DECIMAL(8,3);

  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
    GET DIAGNOSTICS CONDITION 1 p_error_message = MESSAGE_TEXT;
    ROLLBACK;
    SET p_imported = 0;
  END;

  SET p_imported = 0;
  SET p_rejected = 0;
  SET p_error_message = '';

  -- Normalize staged values once (trims stray whitespace / CR characters)
  UPDATE stg_diamonds_import
  SET csv_cut_grade = TRIM(csv_cut_grade),
      csv_color_grade = UPPER(TRIM(csv_color_grade)),
      csv_clarity_grade = UPPER(TRIM(csv_clarity_grade)),
      csv_certification_status = UPPER(TRIM(REPLACE(csv_certification_status, '\r', '')));

  -- Rows that pass numeric and GIA 4Cs validation
  DROP TEMPORARY TABLE IF EXISTS tmp_valid_import;
  CREATE TEMPORARY TABLE tmp_valid_import AS
  SELECT
    CONCAT('SKU-GIA-', s.csv_diamond_id) AS sku,
    ROUND(CAST(s.csv_carat_weight AS DECIMAL(8,3)), 2) AS carat,
    cu.Grade AS cut_grade,
    co.Grade AS color_grade,
    cl.Grade AS clarity_grade,
    CAST(s.csv_depth_percent AS DECIMAL(5,2)) AS depth_pct,
    CAST(s.csv_table_percent AS DECIMAL(5,2)) AS table_pct,
    CAST(s.csv_length_mm AS DECIMAL(5,2)) AS length_mm,
    CAST(s.csv_width_mm AS DECIMAL(5,2)) AS width_mm,
    CAST(s.csv_depth_mm AS DECIMAL(5,2)) AS depth_mm,
    CAST(s.csv_price_usd AS DECIMAL(12,2)) AS price_usd,
    cu.multiplier * co.multiplier * cl.multiplier AS grade_multiplier,
    s.csv_certification_status = 'CERTIFIED' AS certified
  FROM stg_diamonds_import s
  JOIN CUT cu ON cu.Grade = s.csv_cut_grade
  JOIN COLOR co ON co.Grade = s.csv_color_grade
  JOIN CLARITY cl ON cl.Grade = s.csv_clarity_grade
  WHERE s.csv_diamond_id REGEXP '^[0-9]+$'
    AND s.csv_carat_weight REGEXP '^[0-9]+(\\.[0-9]+)?$'
    AND s.csv_price_usd REGEXP '^[0-9]+(\\.[0-9]+)?$'
    AND CAST(s.csv_carat_weight AS DECIMAL(8,3)) >= 0.01
    AND CAST(s.csv_price_usd AS DECIMAL(12,2)) > 0;

  SELECT COUNT(*) INTO v_staged FROM stg_diamonds_import;
  SELECT COUNT(*) INTO v_valid FROM tmp_valid_import;
  SET p_rejected = v_staged - v_valid;

  -- Drop rows already imported on a previous run
  DELETE t FROM tmp_valid_import t JOIN DIAMONDS d ON d.sku = t.sku;

  IF EXISTS (SELECT 1 FROM tmp_valid_import) THEN
    START TRANSACTION;

    SELECT supplier_id INTO v_supplier_id
    FROM SUPPLIERS
    WHERE name = 'CSV Import Default'
    LIMIT 1;

    IF v_supplier_id IS NULL THEN
      INSERT INTO SUPPLIERS (name, country, contact_email)
      VALUES ('CSV Import Default', 'Unknown', 'import@diamonds.example');
      SET v_supplier_id = LAST_INSERT_ID();
    END IF;

    -- One rough-stone batch per import run, weighing the sum of its diamonds
    SELECT SUM(carat) INTO v_total_carat FROM tmp_valid_import;
    INSERT INTO ROUGH_STONES (supplier_id, received_date, weight_carat, cost_usd, `status`)
    VALUES (v_supplier_id, CURRENT_DATE(), v_total_carat, 0, 'CUT');
    SET v_rough_id = LAST_INSERT_ID();

    INSERT INTO DIAMONDS (
      sku, rough_id, carat, cut_grade, color_grade, clarity_grade,
      depth_pct, table_pct, length_mm, width_mm, depth_mm,
      base_price_per_carat, price_usd, `status`, certified, certification_number
    )
    SELECT
      sku, v_rough_id, carat, cut_grade, color_grade, clarity_grade,
      depth_pct, table_pct, length_mm, width_mm, depth_mm,
      ROUND(price_usd / (carat * grade_multiplier), 2),
      price_usd, 'AVAILABLE', certified, NULL
    FROM tmp_valid_import;

    SET p_imported = ROW_COUNT();
    COMMIT;
  END IF;

  DROP TEMPORARY TABLE IF EXISTS tmp_valid_import;

END$$

DELIMITER ;
