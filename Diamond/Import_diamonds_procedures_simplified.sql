-- ========================================================================
-- Diamond CSV Direct Data Import Script (SIMPLIFIED)
-- ========================================================================
-- Purpose: Direct import of diamonds from Diamonds Prices2022.csv
-- No validation, no complexity - just load and insert
-- 
-- CSV Structure:
-- ,carat,cut,color,clarity,depth,table,price,x,y,z
-- ========================================================================

USE Diamond_company;

DELIMITER $$

-- ========================================================================
-- Temporary table for LOAD DATA INFILE
-- ========================================================================
DROP TABLE IF EXISTS temp_csv_import;
CREATE TABLE temp_csv_import (
  csv_carat VARCHAR(20),
  csv_cut VARCHAR(20),
  csv_color VARCHAR(20),
  csv_clarity VARCHAR(20),
  csv_depth VARCHAR(20),
  csv_table VARCHAR(20),
  csv_price VARCHAR(20),
  csv_x VARCHAR(20),
  csv_y VARCHAR(20),
  csv_z VARCHAR(20)
) ENGINE=InnoDB$$

-- ========================================================================
-- Main Import Procedure
-- ========================================================================
-- Usage: CALL sp_import_diamonds('/path/to/Diamonds Prices2022.csv');
-- Or:    CALL sp_import_diamonds(NULL);  -- Uses default path
-- ========================================================================
CREATE PROCEDURE sp_import_diamonds(
  IN p_csv_file_path VARCHAR(512)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_file_path VARCHAR(512);
  DECLARE v_supplier_id INT;
  DECLARE v_rough_id INT;
  DECLARE v_imported_count INT DEFAULT 0;
  
  SET v_file_path = IFNULL(p_csv_file_path, '/Users/emmanuel/Desktop/Git/SQL/SQL-Projects/Diamond/Diamonds Prices2022.csv');
  
  -- Enable local file loading
  SET SESSION local_infile = 1;
  
  -- ================================================================
  -- Step 1: Clear and load CSV to temporary table
  -- ================================================================
  TRUNCATE TABLE temp_csv_import;
  
  SET @load_sql = CONCAT(
    'LOAD DATA LOCAL INFILE \'', v_file_path, '\' ',
    'INTO TABLE temp_csv_import ',
    'FIELDS TERMINATED BY \',\' ENCLOSED BY \'"\'',
    ' LINES TERMINATED BY \'\\n\' ',
    'IGNORE 1 ROWS '
  );
  
  PREPARE load_stmt FROM @load_sql;
  EXECUTE load_stmt;
  DEALLOCATE PREPARE load_stmt;
  
  -- ================================================================
  -- Step 2: Ensure supplier exists
  -- ================================================================
  SELECT COALESCE(supplier_id, 0) INTO v_supplier_id 
  FROM SUPPLIERS 
  WHERE name = 'CSV Import Default' 
  LIMIT 1;

  IF v_supplier_id = 0 THEN
    INSERT INTO SUPPLIERS (name, country, contact_email)
    VALUES ('CSV Import Default', 'Unknown', 'import@diamonds.local');
    SET v_supplier_id = LAST_INSERT_ID();
  END IF;

  -- ================================================================
  -- Step 3: Create rough stone for import batch
  -- ================================================================
  INSERT INTO ROUGH_STONES (supplier_id, received_date, weight_carat, cost_usd, `status`)
  VALUES (v_supplier_id, DATE('2022-01-01'), 100000, 0, 'RECEIVED');
  SET v_rough_id = LAST_INSERT_ID();

  -- ================================================================
  -- Step 4: Import diamonds directly from temporary table
  -- ================================================================
  START TRANSACTION;
  
  INSERT INTO DIAMONDS (
    sku,
    rough_id,
    carat,
    cut_grade,
    color_grade,
    clarity_grade,
    depth,
    table_pct,
    base_price_per_carat,
    price_usd,
    `status`,
    certified
  )
  SELECT
    CONCAT('SKU-CSV-', ROW_NUMBER() OVER (ORDER BY csv_carat)) as sku,
    v_rough_id as rough_id,
    CAST(csv_carat AS DECIMAL(8,3)) as carat,
    CASE UPPER(csv_cut)
      WHEN 'IDEAL' THEN 'Excellent'
      WHEN 'PREMIUM' THEN 'Very Good'
      WHEN 'VERY GOOD' THEN 'Very Good'
      WHEN 'GOOD' THEN 'Good'
      WHEN 'FAIR' THEN 'Fair'
      WHEN 'POOR' THEN 'Poor'
      ELSE 'Good'
    END as cut_grade,
    UPPER(csv_color) as color_grade,
    UPPER(csv_clarity) as clarity_grade,
    CAST(csv_depth AS DECIMAL(5,2)) as depth,
    CAST(csv_table AS DECIMAL(5,2)) as table_pct,
    ROUND(CAST(csv_price AS DECIMAL(12,2)) / CAST(csv_carat AS DECIMAL(8,3)), 2) as base_price_per_carat,
    CAST(csv_price AS DECIMAL(12,2)) as price_usd,
    'AVAILABLE' as `status`,
    FALSE as certified
  FROM temp_csv_import
  WHERE csv_carat IS NOT NULL 
    AND csv_price IS NOT NULL
    AND CAST(csv_price AS DECIMAL(12,2)) > 0
    AND CAST(csv_carat AS DECIMAL(8,3)) > 0;
  
  COMMIT;
  
  SELECT ROW_COUNT() INTO v_imported_count;
  
  SELECT CONCAT('Successfully imported ', v_imported_count, ' diamonds') as import_result;

END$$

-- ========================================================================
-- How to use this import script:
-- ========================================================================
-- 1. Ensure MySQL has local_infile enabled:
--    SET GLOBAL local_infile = 1;
--
-- 2. Run import with default CSV path:
--    CALL sp_import_diamonds(NULL);
--
-- 3. Or specify custom CSV path:
--    CALL sp_import_diamonds('/path/to/your/Diamonds_Prices2022.csv');
--
-- 4. Query imported data:
--    SELECT COUNT(*) as total_diamonds FROM DIAMONDS WHERE `status` = 'AVAILABLE';
--    SELECT * FROM DIAMONDS ORDER BY price_usd DESC LIMIT 10;
-- ========================================================================

DELIMITER ;
