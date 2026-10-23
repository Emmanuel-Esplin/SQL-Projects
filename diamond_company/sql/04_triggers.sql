-- ========================================================================
-- Triggers
-- ========================================================================
-- Run after 03_stored_procedures.sql. Change detection uses the NULL-safe
-- operator (<=>) because cut_grade and certification_number may be NULL.
-- ========================================================================

USE Diamond_company;

DROP TRIGGER IF EXISTS trg_diamonds_before_insert;
DROP TRIGGER IF EXISTS trg_diamonds_after_update;
DROP TRIGGER IF EXISTS trg_diamonds_after_delete;
DROP TRIGGER IF EXISTS trg_rough_stones_after_update;
DROP TRIGGER IF EXISTS trg_orders_after_update;
DROP TRIGGER IF EXISTS trg_order_items_before_insert;
DROP TRIGGER IF EXISTS trg_order_items_after_insert;
DROP TRIGGER IF EXISTS trg_work_orders_after_update;

DELIMITER $$

-- ========================================================================
-- DIAMONDS: Before Insert Trigger
-- ========================================================================
-- Purpose: Auto-generate SKU if not provided
-- Note: No FOR UPDATE needed in triggers (row is already locked)
-- ========================================================================
CREATE TRIGGER trg_diamonds_before_insert 
BEFORE INSERT ON DIAMONDS
FOR EACH ROW
BEGIN
  -- Auto-generate SKU if not provided or empty
  IF NEW.sku IS NULL OR NEW.sku = '' THEN
    SET NEW.sku = CONCAT('SKU-', UUID());
  END IF;

  -- Ensure created_at is set
  IF NEW.created_at IS NULL THEN
    SET NEW.created_at = CURRENT_TIMESTAMP;
  END IF;

  -- Ensure updated_at is set
  IF NEW.updated_at IS NULL THEN
    SET NEW.updated_at = CURRENT_TIMESTAMP;
  END IF;

  -- Validate carat
  IF NEW.carat <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Carat must be greater than 0';
  END IF;

  -- Validate base price
  IF NEW.base_price_per_carat < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Base price cannot be negative';
  END IF;

  -- Validate color grade
  IF NEW.color_grade IS NULL OR NEW.color_grade NOT BETWEEN 'D' AND 'Z' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid color grade (D-Z)';
  END IF;

END$$

-- ========================================================================
-- DIAMONDS: After Update Trigger
-- ========================================================================
-- Purpose: Flag a price recompute when the 4Cs or base price change
-- (triggers cannot call sp_compute_price), and maintain the audit log
-- ========================================================================
CREATE TRIGGER trg_diamonds_after_update 
AFTER UPDATE ON DIAMONDS
FOR EACH ROW
BEGIN
  DECLARE v_price_changed BOOLEAN DEFAULT FALSE;

  -- Check if price-affecting fields (the 4Cs or base price) changed
  IF NOT (OLD.carat <=> NEW.carat
    AND OLD.cut_grade <=> NEW.cut_grade
    AND OLD.color_grade <=> NEW.color_grade
    AND OLD.clarity_grade <=> NEW.clarity_grade
    AND OLD.base_price_per_carat <=> NEW.base_price_per_carat) THEN
    SET v_price_changed = TRUE;
  END IF;

  -- If price-affecting fields changed, recompute price
  -- We cannot call procedures in triggers directly, so we log for async processing
  IF v_price_changed THEN
    INSERT INTO AUDIT_LOG(table_name, action, row_id, payload, changed_by)
    VALUES ('DIAMONDS', 'UPDATE', NEW.diamond_id, 
      JSON_OBJECT(
        'event', 'price_update_needed',
        'old_carat', OLD.carat,
        'new_carat', NEW.carat,
        'old_cut', OLD.cut_grade,
        'new_cut', NEW.cut_grade,
        'old_color', OLD.color_grade,
        'new_color', NEW.color_grade,
        'old_clarity', OLD.clarity_grade,
        'new_clarity', NEW.clarity_grade,
        'old_base_price', OLD.base_price_per_carat,
        'new_base_price', NEW.base_price_per_carat
      ),
      'SYSTEM_TRIGGER');
  END IF;

  -- Log all status changes
  IF OLD.status <> NEW.status THEN
    INSERT INTO AUDIT_LOG(table_name, action, row_id, payload, changed_by)
    VALUES ('DIAMONDS', 'UPDATE', NEW.diamond_id, 
      JSON_OBJECT(
        'event', 'status_change',
        'old_status', OLD.status,
        'new_status', NEW.status,
        'old_price', OLD.price_usd,
        'new_price', NEW.price_usd
      ),
      'SYSTEM_TRIGGER');
  END IF;

  -- Log certification changes
  IF NOT (OLD.certified <=> NEW.certified AND OLD.certification_number <=> NEW.certification_number) THEN
    INSERT INTO AUDIT_LOG(table_name, action, row_id, payload, changed_by)
    VALUES ('DIAMONDS', 'UPDATE', NEW.diamond_id, 
      JSON_OBJECT(
        'event', 'certification_change',
        'old_certified', OLD.certified,
        'new_certified', NEW.certified,
        'old_cert_num', OLD.certification_number,
        'new_cert_num', NEW.certification_number
      ),
      'SYSTEM_TRIGGER');
  END IF;

END$$

-- ========================================================================
-- DIAMONDS: After Delete Trigger
-- ========================================================================
-- Purpose: Audit trail for deleted diamonds
-- ========================================================================
CREATE TRIGGER trg_diamonds_after_delete 
AFTER DELETE ON DIAMONDS
FOR EACH ROW
BEGIN
  INSERT INTO AUDIT_LOG(table_name, action, row_id, payload, changed_by)
  VALUES ('DIAMONDS', 'DELETE', OLD.diamond_id,
    JSON_OBJECT(
      'sku', OLD.sku,
      'rough_id', OLD.rough_id,
      'carat', OLD.carat,
      'cut_grade', OLD.cut_grade,
      'color_grade', OLD.color_grade,
      'clarity_grade', OLD.clarity_grade,
      'status', OLD.status,
      'price_usd', OLD.price_usd,
      'certified', OLD.certified,
      'certification_number', OLD.certification_number
    ),
    'SYSTEM_TRIGGER');
END$$

-- ========================================================================
-- ROUGH_STONES: After Update Trigger
-- ========================================================================
-- Purpose: Update audit log when rough stone status changes
-- ========================================================================
CREATE TRIGGER trg_rough_stones_after_update 
AFTER UPDATE ON ROUGH_STONES
FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO AUDIT_LOG(table_name, action, row_id, payload, changed_by)
    VALUES ('ROUGH_STONES', 'UPDATE', NEW.rough_id,
      JSON_OBJECT(
        'event', 'status_change',
        'supplier_id', NEW.supplier_id,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'weight_carat', NEW.weight_carat,
        'cost_usd', NEW.cost_usd
      ),
      'SYSTEM_TRIGGER');
  END IF;
END$$

-- ========================================================================
-- ORDERS: After Update Trigger
-- ========================================================================
-- Purpose: Audit trail for order status changes
-- ========================================================================
CREATE TRIGGER trg_orders_after_update 
AFTER UPDATE ON ORDERS
FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO AUDIT_LOG(table_name, action, row_id, payload, changed_by)
    VALUES ('ORDERS', 'UPDATE', NEW.order_id,
      JSON_OBJECT(
        'event', 'status_change',
        'customer_id', NEW.customer_id,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'old_amount', OLD.total_amount,
        'new_amount', NEW.total_amount
      ),
      'SYSTEM_TRIGGER');
  END IF;
END$$

-- ========================================================================
-- ORDER_ITEMS: Before Insert Trigger
-- ========================================================================
-- Purpose: Validate diamond availability before creating order item
-- Note: This validation is also done in sp_place_order, but we add it here
--       for defense-in-depth (prevents direct INSERT bypassing stored proc)
-- ========================================================================
CREATE TRIGGER trg_order_items_before_insert 
BEFORE INSERT ON ORDER_ITEMS
FOR EACH ROW
BEGIN
  DECLARE v_found INT DEFAULT 0;

  -- Verify diamond exists
  SELECT COUNT(*) INTO v_found FROM DIAMONDS WHERE diamond_id = NEW.diamond_id;
  IF v_found = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Diamond does not exist';
  END IF;

  -- Verify order exists
  SELECT COUNT(*) INTO v_found FROM ORDERS WHERE order_id = NEW.order_id;
  IF v_found = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order does not exist';
  END IF;

  -- Verify quantity is valid
  IF NEW.quantity IS NULL OR NEW.quantity <= 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantity must be greater than 0';
  END IF;

  -- Verify price is valid
  IF NEW.price_at_sale < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Price cannot be negative';
  END IF;

  -- Set created_at
  IF NEW.created_at IS NULL THEN
    SET NEW.created_at = CURRENT_TIMESTAMP;
  END IF;

END$$

-- ========================================================================
-- ORDER_ITEMS: After Insert Trigger
-- ========================================================================
-- Purpose: Audit trail for order items
-- ========================================================================
CREATE TRIGGER trg_order_items_after_insert 
AFTER INSERT ON ORDER_ITEMS
FOR EACH ROW
BEGIN
  INSERT INTO AUDIT_LOG(table_name, action, row_id, payload, changed_by)
  VALUES ('ORDER_ITEMS', 'INSERT', NEW.order_item_id,
    JSON_OBJECT(
      'event', 'order_item_created',
      'order_id', NEW.order_id,
      'diamond_id', NEW.diamond_id,
      'price_at_sale', NEW.price_at_sale,
      'quantity', NEW.quantity
    ),
    'SYSTEM_TRIGGER');
END$$

-- ========================================================================
-- WORK_ORDERS: After Update Trigger
-- ========================================================================
-- Purpose: Audit trail for work order status changes
-- ========================================================================
CREATE TRIGGER trg_work_orders_after_update 
AFTER UPDATE ON WORK_ORDERS
FOR EACH ROW
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO AUDIT_LOG(table_name, action, row_id, payload, changed_by)
    VALUES ('WORK_ORDERS', 'UPDATE', NEW.work_order_id,
      JSON_OBJECT(
        'event', 'status_change',
        'rough_id', NEW.rough_id,
        'employee_id', NEW.employee_id,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'start_date', NEW.start_date,
        'end_date', NEW.end_date
      ),
      'SYSTEM_TRIGGER');
  END IF;
END$$

DELIMITER ;

-- ========================================================================
-- Verification Query: Check all triggers
-- ========================================================================
-- Run this to verify all triggers were created correctly:
-- SELECT TRIGGER_SCHEMA, TRIGGER_NAME, EVENT_MANIPULATION, EVENT_OBJECT_TABLE
-- FROM INFORMATION_SCHEMA.TRIGGERS
-- WHERE TRIGGER_SCHEMA = 'Diamond_company'
-- ORDER BY EVENT_OBJECT_TABLE, EVENT_MANIPULATION;

