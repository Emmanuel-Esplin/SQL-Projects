
USE Diamond_company;

SET SESSION sql_mode = 'STRICT_TRANS_TABLES';

DELIMITER $$

-- ========================================================================
-- Utility: Log errors to audit trail
-- ========================================================================
CREATE PROCEDURE sp_log_error(
  IN p_error_code INT,
  IN p_error_message VARCHAR(255),
  IN p_context VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  INSERT INTO AUDIT_LOG (table_name, action, row_id, payload, changed_by)
  VALUES (
    'ERROR_LOG',
    'INSERT',
    p_error_code,
    JSON_OBJECT('error_code', p_error_code, 'message', p_error_message, 'context', p_context),
    'SYSTEM'
  );
END$$

-- ========================================================================
-- Core: Compute Diamond Price
-- ========================================================================
-- Purpose: Calculate final price based on 4Cs and base price
-- Lock order: CUT -> COLOR -> CLARITY (all reference tables, no conflicts)
-- ========================================================================
CREATE PROCEDURE sp_compute_price(
  IN p_diamond_id INT,
  OUT p_success TINYINT(1),
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_carat DECIMAL(5, 2);
  DECLARE v_cut VARCHAR(20);
  DECLARE v_color CHAR(1);
  DECLARE v_clarity VARCHAR(10);
  DECLARE v_base DECIMAL(10, 2);
  DECLARE v_m_cut DECIMAL(6, 3) DEFAULT 1.0;
  DECLARE v_m_color DECIMAL(6, 3) DEFAULT 1.0;
  DECLARE v_m_clarity DECIMAL(6, 3) DEFAULT 1.0;
  DECLARE v_price DECIMAL(12, 2);
  DECLARE v_retry_count INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_not_found INT DEFAULT 0;
  DECLARE v_sql_error INT DEFAULT 0;
  
  DECLARE CONTINUE HANDLER FOR SQLSTATE '40001' BEGIN
    SET v_retry_count = v_retry_count + 1;
  END;

  DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN
    SET v_not_found = 1;
  END;

  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    SET v_sql_error = 1;

  SET p_success = FALSE;
  SET p_error_message = '';
  
  retry_loop: LOOP
    IF v_retry_count > v_max_retries THEN
      SET p_error_message = CONCAT('Max retries exceeded for diamond_id=', p_diamond_id);
      CALL sp_log_error(1213, p_error_message, 'sp_compute_price');
      LEAVE retry_loop;
    END IF;

    SET v_sql_error = 0;
    START TRANSACTION;

    -- Lock diamond for read (gets all 4Cs)
    SELECT carat, cut_grade, color_grade, clarity_grade, base_price_per_carat
    INTO v_carat, v_cut, v_color, v_clarity, v_base
    FROM DIAMONDS 
    WHERE diamond_id = p_diamond_id 
    FOR UPDATE;

    IF v_not_found = 1 THEN
      ROLLBACK;
      SET p_error_message = CONCAT('Diamond not found: ', p_diamond_id);
      LEAVE retry_loop;
    END IF;

    IF v_sql_error = 1 THEN
      ROLLBACK;
      SET p_error_message = 'Transaction error during price computation';
      LEAVE retry_loop;
    END IF;

    -- Lock reference tables for read (multipliers)
    IF v_cut IS NOT NULL THEN
      SET v_not_found = 0;
      SELECT multiplier INTO v_m_cut FROM CUT WHERE Grade = v_cut LOCK IN SHARE MODE;
      IF v_not_found = 1 THEN
        SET v_m_cut = 1.0;
      END IF;
    END IF;

    IF v_color IS NOT NULL THEN
      SET v_not_found = 0;
      SELECT multiplier INTO v_m_color FROM COLOR WHERE Grade = v_color LOCK IN SHARE MODE;
      IF v_not_found = 1 THEN
        SET v_m_color = 1.0;
      END IF;
    END IF;

    IF v_clarity IS NOT NULL THEN
      SET v_not_found = 0;
      SELECT multiplier INTO v_m_clarity FROM CLARITY WHERE Grade = v_clarity LOCK IN SHARE MODE;
      IF v_not_found = 1 THEN
        SET v_m_clarity = 1.0;
      END IF;
    END IF;

    -- Calculate price
    SET v_price = ROUND(v_carat * v_base * v_m_cut * v_m_color * v_m_clarity, 2);

    -- Update diamond price
    UPDATE DIAMONDS 
    SET price_usd = v_price, updated_at = CURRENT_TIMESTAMP
    WHERE diamond_id = p_diamond_id;

    COMMIT;
    SET p_success = TRUE;
    LEAVE retry_loop;

  END LOOP;

END$$

-- ========================================================================
-- Grade Diamond and Recompute Price
-- ========================================================================
-- Purpose: Apply GIA grades to a diamond and recalculate price
-- Lock order: DIAMONDS (holds write lock throughout)
-- ========================================================================
CREATE PROCEDURE sp_grade_diamond(
  IN p_diamond_id INT,
  IN p_cut VARCHAR(20),
  IN p_color CHAR(1),
  IN p_clarity VARCHAR(10),
  OUT p_success TINYINT(1),
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_retry_count INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_sql_error INT DEFAULT 0;
  
  DECLARE CONTINUE HANDLER FOR SQLSTATE '40001' BEGIN
    SET v_retry_count = v_retry_count + 1;
  END;

  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    SET v_sql_error = 1;

  SET p_success = FALSE;
  SET p_error_message = '';

  -- Validate inputs
  IF p_color IS NULL OR p_color NOT BETWEEN 'D' AND 'Z' THEN
    SET p_error_message = 'Invalid color grade';
    SET p_success = FALSE;
  ELSE
    retry_loop: LOOP
      IF v_retry_count > v_max_retries THEN
        SET p_error_message = CONCAT('Max retries exceeded for diamond_id=', p_diamond_id);
        LEAVE retry_loop;
      END IF;

      SET v_sql_error = 0;
      START TRANSACTION;

      -- Update diamond with grades
      UPDATE DIAMONDS
      SET cut_grade = p_cut,
          color_grade = p_color,
          clarity_grade = p_clarity,
          updated_at = CURRENT_TIMESTAMP
      WHERE diamond_id = p_diamond_id;

      IF v_sql_error = 0 THEN
        COMMIT;

        -- Recompute price in separate transaction to avoid nested transactions
        CALL sp_compute_price(p_diamond_id, @price_success, @price_error);
        
        SET p_success = @price_success;
        SET p_error_message = @price_error;
        LEAVE retry_loop;
      ELSE
        ROLLBACK;
        SET p_error_message = 'Transaction error during grading';
      END IF;

    END LOOP;
  END IF;

END$$

-- ========================================================================
-- Place Order and Reserve Stone
-- ========================================================================
-- Purpose: Create order and reserve diamond atomically
-- Lock order: CUSTOMERS (for validation) -> ORDERS -> DIAMONDS -> ORDER_ITEMS
-- This order prevents deadlocks with sp_fulfill_order
-- ========================================================================
CREATE PROCEDURE sp_place_order(
  IN p_customer_id INT,
  IN p_diamond_id INT,
  OUT p_order_id INT,
  OUT p_success TINYINT(1),
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_price DECIMAL(12,2);
  DECLARE v_customer_exists INT;
  DECLARE v_not_found INT DEFAULT 0;
  DECLARE v_retry_count INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_sql_error INT DEFAULT 0;
  
  DECLARE CONTINUE HANDLER FOR SQLSTATE '40001' BEGIN
    SET v_retry_count = v_retry_count + 1;
  END;

  DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN
    SET v_not_found = 1;
  END;

  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    SET v_sql_error = 1;

  SET p_order_id = 0;
  SET p_success = FALSE;
  SET p_error_message = '';

  -- Validate customer exists
  SELECT COUNT(*) INTO v_customer_exists FROM CUSTOMERS WHERE customer_id = p_customer_id;
  IF v_customer_exists = 0 THEN
    SET p_error_message = CONCAT('Customer not found: ', p_customer_id);
    SET p_success = FALSE;
  ELSE
    retry_loop: LOOP
      IF v_retry_count > v_max_retries THEN
        SET p_error_message = CONCAT('Max retries exceeded for order placement');
        LEAVE retry_loop;
      END IF;

      SET v_sql_error = 0;
      START TRANSACTION;

      -- Lock diamond BEFORE creating order (prevents race conditions)
      SET v_not_found = 0;
      SELECT `status`, price_usd INTO v_status, v_price
      FROM DIAMONDS 
      WHERE diamond_id = p_diamond_id 
      FOR UPDATE;

      IF v_not_found = 1 THEN
        ROLLBACK;
        SET p_error_message = CONCAT('Diamond not found: ', p_diamond_id);
        LEAVE retry_loop;
      END IF;

      IF v_status <> 'AVAILABLE' THEN
        ROLLBACK;
        SET p_error_message = CONCAT('Diamond not available. Status: ', v_status);
        LEAVE retry_loop;
      END IF;

      IF v_sql_error = 0 THEN
        -- Create order
        INSERT INTO ORDERS(customer_id, order_date, `status`, total_amount)
        VALUES(p_customer_id, CURRENT_DATE(), 'PENDING', v_price);
        
        SET p_order_id = LAST_INSERT_ID();

        -- Create order item
        INSERT INTO ORDER_ITEMS(order_id, diamond_id, price_at_sale, quantity)
        VALUES(p_order_id, p_diamond_id, v_price, 1);

        -- Reserve diamond
        UPDATE DIAMONDS 
        SET `status` = 'RESERVED', updated_at = CURRENT_TIMESTAMP
        WHERE diamond_id = p_diamond_id;

        -- Update order total
        UPDATE ORDERS
        SET total_amount = (
          SELECT SUM(price_at_sale * quantity) FROM ORDER_ITEMS WHERE order_id = p_order_id
        )
        WHERE order_id = p_order_id;
      END IF;

      IF v_sql_error = 1 THEN
        ROLLBACK;
        SET p_error_message = 'Transaction error during order placement';
      ELSE
        COMMIT;
        SET p_success = TRUE;
        LEAVE retry_loop;
      END IF;

    END LOOP;
  END IF;

END$$

-- ========================================================================
-- Fulfill Order (Mark as Paid/Shipped/Cancelled)
-- ========================================================================
-- Purpose: Update order status and diamond status atomically
-- Lock order: ORDERS -> ORDER_ITEMS -> DIAMONDS
-- This order prevents deadlocks with sp_place_order
-- ========================================================================
CREATE PROCEDURE sp_fulfill_order(
  IN p_order_id INT,
  IN p_new_status VARCHAR(20),
  OUT p_success TINYINT(1),
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_diamond_id INT;
  DECLARE v_retry_count INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_order_exists INT;
  DECLARE v_sql_error INT DEFAULT 0;
  DECLARE v_not_found INT DEFAULT 0;

  DECLARE CONTINUE HANDLER FOR SQLSTATE '40001' BEGIN
    SET v_retry_count = v_retry_count + 1;
  END;

  DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN
    SET v_not_found = 1;
  END;

  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    SET v_sql_error = 1;

  SET p_success = FALSE;
  SET p_error_message = '';

  -- Validate order exists
  SELECT COUNT(*) INTO v_order_exists FROM ORDERS WHERE order_id = p_order_id;
  IF v_order_exists = 0 THEN
    SET p_error_message = CONCAT('Order not found: ', p_order_id);
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = p_error_message;
  END IF;

  retry_loop: LOOP
    IF v_retry_count > v_max_retries THEN
      SET p_error_message = CONCAT('Max retries exceeded for order fulfillment');
      LEAVE retry_loop;
    END IF;

    SET v_sql_error = 0;
    START TRANSACTION;

    -- Lock order
    UPDATE ORDERS 
    SET `status` = p_new_status, updated_at = CURRENT_TIMESTAMP
    WHERE order_id = p_order_id;

    -- Get diamond_id from order items
    SET v_not_found = 0;
    SELECT diamond_id INTO v_diamond_id
    FROM ORDER_ITEMS 
    WHERE order_id = p_order_id 
    LIMIT 1 
    FOR UPDATE;

    IF v_not_found = 1 OR v_diamond_id IS NULL THEN
      ROLLBACK;
      SET p_error_message = CONCAT('No items found for order: ', p_order_id);
      LEAVE retry_loop;
    END IF;

    IF v_sql_error = 0 THEN
      -- Update diamond status based on order status
      IF p_new_status IN ('PAID', 'SHIPPED') THEN
        UPDATE DIAMONDS 
        SET `status` = 'SOLD', updated_at = CURRENT_TIMESTAMP
        WHERE diamond_id = v_diamond_id;
      ELSEIF p_new_status = 'CANCELLED' THEN
        UPDATE DIAMONDS 
        SET `status` = 'AVAILABLE', updated_at = CURRENT_TIMESTAMP
        WHERE diamond_id = v_diamond_id;
      END IF;
    END IF;

    IF v_sql_error = 1 THEN
      ROLLBACK;
      SET p_error_message = 'Transaction error during order fulfillment';
    ELSE
      COMMIT;
      SET p_success = TRUE;
      LEAVE retry_loop;
    END IF;

  END LOOP;

END$$

-- ========================================================================
-- Bulk Create Daily Inventory Snapshot
-- ========================================================================
-- Purpose: Create daily inventory snapshot for reporting
-- Lock order: DIAMONDS (shared lock) -> INVENTORY_SNAPSHOT
-- ========================================================================
CREATE PROCEDURE sp_create_inventory_snapshot(
  IN p_snapshot_date DATE,
  OUT p_success TINYINT(1),
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_retry_count INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_exists INT;
  DECLARE v_sql_error INT DEFAULT 0;

  DECLARE CONTINUE HANDLER FOR SQLSTATE '40001' BEGIN
    SET v_retry_count = v_retry_count + 1;
  END;

  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    SET v_sql_error = 1;

  -- Use provided date or today
  IF p_snapshot_date IS NULL THEN
    SET p_snapshot_date = CURRENT_DATE();
  END IF;

  -- Check if snapshot already exists
  SELECT COUNT(*) INTO v_exists FROM INVENTORY_SNAPSHOT 
  WHERE snapshot_date = p_snapshot_date;
  
  IF v_exists > 0 THEN
    SET p_error_message = CONCAT('Snapshot already exists for date: ', p_snapshot_date);
    SET p_success = FALSE;
  ELSE
    retry_loop: LOOP
      IF v_retry_count > v_max_retries THEN
        SET p_error_message = CONCAT('Max retries exceeded for snapshot creation');
        LEAVE retry_loop;
      END IF;

      SET v_sql_error = 0;
      START TRANSACTION;

      INSERT INTO INVENTORY_SNAPSHOT (
        snapshot_date,
        total_available,
        total_reserved,
        total_sold,
        total_value_usd,
        total_cost_usd
      )
      SELECT
        p_snapshot_date,
        COALESCE(SUM(CASE WHEN d.`status` = 'AVAILABLE' THEN 1 ELSE 0 END), 0) as total_available,
        COALESCE(SUM(CASE WHEN d.`status` = 'RESERVED' THEN 1 ELSE 0 END), 0) as total_reserved,
        COALESCE(SUM(CASE WHEN d.`status` = 'SOLD' THEN 1 ELSE 0 END), 0) as total_sold,
        COALESCE(SUM(d.price_usd), 0) as total_value_usd,
        COALESCE(SUM(rs.cost_usd), 0) as total_cost_usd
      FROM DIAMONDS d
      LEFT JOIN ROUGH_STONES rs ON d.rough_id = rs.rough_id;

      IF v_sql_error = 1 THEN
        ROLLBACK;
        SET p_error_message = 'Transaction error during snapshot creation';
      ELSE
        COMMIT;
        SET p_success = TRUE;
        LEAVE retry_loop;
      END IF;

    END LOOP retry_loop;
  END IF;

END$$

DELIMITER ;


