-- ========================================================================
-- Stored Procedures
-- ========================================================================
-- Run after 02_reference_data.sql.
--
-- Retry pattern used by every write procedure:
--   * Each attempt runs inside its own BEGIN ... END block with EXIT handlers.
--   * Deadlock (SQLSTATE 40001 / error 1213) or lock wait timeout (1205):
--     roll back, back off 0.1s * attempt, retry (max 3 retries).
--   * Any other error: roll back and return its message in p_error_message.
--   * Business-rule failures (not found, not available): roll back and
--     LEAVE the attempt block without retrying.
-- ========================================================================

USE Diamond_company;

DROP PROCEDURE IF EXISTS sp_log_error;
DROP PROCEDURE IF EXISTS sp_compute_price;
DROP PROCEDURE IF EXISTS sp_grade_diamond;
DROP PROCEDURE IF EXISTS sp_place_order;
DROP PROCEDURE IF EXISTS sp_fulfill_order;
DROP PROCEDURE IF EXISTS sp_create_inventory_snapshot;

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
-- Core: Compute Diamond Price from the GIA 4Cs
-- ========================================================================
-- price_usd = carat * base_price_per_carat * cut_mult * color_mult * clarity_mult
-- An ungraded cut (NULL) uses a multiplier of 1.0.
-- Lock order: DIAMONDS (FOR UPDATE) -> CUT -> COLOR -> CLARITY (FOR SHARE)
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
  DECLARE v_m_cut DECIMAL(6, 3);
  DECLARE v_m_color DECIMAL(6, 3);
  DECLARE v_m_clarity DECIMAL(6, 3);
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_retry TINYINT(1);

  SET p_success = FALSE;
  SET p_error_message = '';

  retry_loop: LOOP
    SET v_attempt = v_attempt + 1;
    SET v_retry = FALSE;

    attempt: BEGIN
      DECLARE EXIT HANDLER FOR SQLSTATE '40001', 1205 BEGIN
        ROLLBACK;
        SET v_retry = TRUE;
      END;
      DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
        GET DIAGNOSTICS CONDITION 1 p_error_message = MESSAGE_TEXT;
        ROLLBACK;
      END;
      -- Missing reference rows leave the default multiplier in place
      DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

      SET v_carat = NULL, v_m_cut = 1.0, v_m_color = 1.0, v_m_clarity = 1.0;
      START TRANSACTION;

      SELECT carat, cut_grade, color_grade, clarity_grade, base_price_per_carat
      INTO v_carat, v_cut, v_color, v_clarity, v_base
      FROM DIAMONDS
      WHERE diamond_id = p_diamond_id
      FOR UPDATE;

      IF v_carat IS NULL THEN
        ROLLBACK;
        SET p_error_message = CONCAT('Diamond not found: ', p_diamond_id);
        LEAVE attempt;
      END IF;

      IF v_cut IS NOT NULL THEN
        SELECT multiplier INTO v_m_cut FROM CUT WHERE Grade = v_cut FOR SHARE;
      END IF;
      SELECT multiplier INTO v_m_color FROM COLOR WHERE Grade = v_color FOR SHARE;
      SELECT multiplier INTO v_m_clarity FROM CLARITY WHERE Grade = v_clarity FOR SHARE;

      UPDATE DIAMONDS
      SET price_usd = ROUND(v_carat * v_base * v_m_cut * v_m_color * v_m_clarity, 2),
          updated_at = CURRENT_TIMESTAMP
      WHERE diamond_id = p_diamond_id;

      COMMIT;
      SET p_success = TRUE;
    END attempt;

    IF p_success OR NOT v_retry THEN
      LEAVE retry_loop;
    END IF;
    IF v_attempt > v_max_retries THEN
      SET p_error_message = CONCAT('Max retries exceeded for diamond_id=', p_diamond_id);
      CALL sp_log_error(1213, p_error_message, 'sp_compute_price');
      LEAVE retry_loop;
    END IF;
    DO SLEEP(0.1 * v_attempt);
  END LOOP;

END$$

-- ========================================================================
-- Grade Diamond (Cut, Color, Clarity) and Recompute Price
-- ========================================================================
-- Grades are validated against the GIA reference tables before any lock
-- is taken. Carat is measured, not graded, so it is not changed here.
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
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_retry TINYINT(1);
  DECLARE v_graded TINYINT(1) DEFAULT FALSE;

  SET p_success = FALSE;
  SET p_error_message = '';

  -- Validate inputs against the GIA scales
  IF p_cut IS NOT NULL AND NOT EXISTS (SELECT 1 FROM CUT WHERE Grade = p_cut) THEN
    SET p_error_message = CONCAT('Invalid GIA cut grade: ', p_cut);
  ELSEIF p_color IS NULL OR NOT EXISTS (SELECT 1 FROM COLOR WHERE Grade = UPPER(p_color)) THEN
    SET p_error_message = CONCAT('Invalid GIA color grade: ', IFNULL(p_color, 'NULL'));
  ELSEIF p_clarity IS NULL OR NOT EXISTS (SELECT 1 FROM CLARITY WHERE Grade = p_clarity) THEN
    SET p_error_message = CONCAT('Invalid GIA clarity grade: ', IFNULL(p_clarity, 'NULL'));
  ELSE
    retry_loop: LOOP
      SET v_attempt = v_attempt + 1;
      SET v_retry = FALSE;

      attempt: BEGIN
        DECLARE EXIT HANDLER FOR SQLSTATE '40001', 1205 BEGIN
          ROLLBACK;
          SET v_retry = TRUE;
        END;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
          GET DIAGNOSTICS CONDITION 1 p_error_message = MESSAGE_TEXT;
          ROLLBACK;
        END;

        START TRANSACTION;

        UPDATE DIAMONDS
        SET cut_grade = p_cut,
            color_grade = UPPER(p_color),
            clarity_grade = UPPER(p_clarity),
            updated_at = CURRENT_TIMESTAMP
        WHERE diamond_id = p_diamond_id;

        IF ROW_COUNT() = 0 AND NOT EXISTS (SELECT 1 FROM DIAMONDS WHERE diamond_id = p_diamond_id) THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Diamond not found: ', p_diamond_id);
          LEAVE attempt;
        END IF;

        COMMIT;
        SET v_graded = TRUE;
      END attempt;

      IF v_graded OR NOT v_retry THEN
        LEAVE retry_loop;
      END IF;
      IF v_attempt > v_max_retries THEN
        SET p_error_message = CONCAT('Max retries exceeded for diamond_id=', p_diamond_id);
        LEAVE retry_loop;
      END IF;
      DO SLEEP(0.1 * v_attempt);
    END LOOP;

    -- Recompute price in a separate transaction (MySQL has no nested transactions)
    IF v_graded THEN
      CALL sp_compute_price(p_diamond_id, p_success, p_error_message);
    END IF;
  END IF;

END$$

-- ========================================================================
-- Place Order and Reserve Stone
-- ========================================================================
-- Purpose: Create order and reserve diamond atomically
-- Lock order: CUSTOMERS (for validation) -> DIAMONDS -> ORDERS -> ORDER_ITEMS
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
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_retry TINYINT(1);

  SET p_order_id = 0;
  SET p_success = FALSE;
  SET p_error_message = '';

  IF NOT EXISTS (SELECT 1 FROM CUSTOMERS WHERE customer_id = p_customer_id) THEN
    SET p_error_message = CONCAT('Customer not found: ', p_customer_id);
  ELSE
    retry_loop: LOOP
      SET v_attempt = v_attempt + 1;
      SET v_retry = FALSE;

      attempt: BEGIN
        DECLARE EXIT HANDLER FOR SQLSTATE '40001', 1205 BEGIN
          ROLLBACK;
          SET v_retry = TRUE;
          SET p_order_id = 0;
        END;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
          GET DIAGNOSTICS CONDITION 1 p_error_message = MESSAGE_TEXT;
          ROLLBACK;
          SET p_order_id = 0;
        END;
        DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

        SET v_status = NULL;
        START TRANSACTION;

        -- Lock diamond BEFORE creating order (prevents double-selling)
        SELECT `status`, price_usd INTO v_status, v_price
        FROM DIAMONDS
        WHERE diamond_id = p_diamond_id
        FOR UPDATE;

        IF v_status IS NULL THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Diamond not found: ', p_diamond_id);
          LEAVE attempt;
        END IF;

        IF v_status <> 'AVAILABLE' THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Diamond not available. Status: ', v_status);
          LEAVE attempt;
        END IF;

        INSERT INTO ORDERS(customer_id, order_date, `status`, total_amount)
        VALUES(p_customer_id, CURRENT_DATE(), 'PENDING', v_price);
        SET p_order_id = LAST_INSERT_ID();

        INSERT INTO ORDER_ITEMS(order_id, diamond_id, price_at_sale, quantity)
        VALUES(p_order_id, p_diamond_id, v_price, 1);

        UPDATE DIAMONDS
        SET `status` = 'RESERVED', updated_at = CURRENT_TIMESTAMP
        WHERE diamond_id = p_diamond_id;

        COMMIT;
        SET p_success = TRUE;
      END attempt;

      IF p_success OR NOT v_retry THEN
        LEAVE retry_loop;
      END IF;
      IF v_attempt > v_max_retries THEN
        SET p_error_message = 'Max retries exceeded for order placement';
        LEAVE retry_loop;
      END IF;
      DO SLEEP(0.1 * v_attempt);
    END LOOP;
  END IF;

END$$

-- ========================================================================
-- Fulfill Order (Mark as Paid/Shipped/Cancelled)
-- ========================================================================
-- Purpose: Update order status and the status of every diamond on it
-- Lock order: ORDERS -> ORDER_ITEMS -> DIAMONDS
-- ========================================================================
CREATE PROCEDURE sp_fulfill_order(
  IN p_order_id INT,
  IN p_new_status VARCHAR(20),
  OUT p_success TINYINT(1),
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_retry TINYINT(1);

  SET p_success = FALSE;
  SET p_error_message = '';

  IF p_new_status IS NULL OR p_new_status NOT IN ('PENDING', 'PAID', 'SHIPPED', 'CANCELLED') THEN
    SET p_error_message = CONCAT('Invalid order status: ', IFNULL(p_new_status, 'NULL'));
  ELSEIF NOT EXISTS (SELECT 1 FROM ORDERS WHERE order_id = p_order_id) THEN
    SET p_error_message = CONCAT('Order not found: ', p_order_id);
  ELSE
    retry_loop: LOOP
      SET v_attempt = v_attempt + 1;
      SET v_retry = FALSE;

      attempt: BEGIN
        DECLARE EXIT HANDLER FOR SQLSTATE '40001', 1205 BEGIN
          ROLLBACK;
          SET v_retry = TRUE;
        END;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
          GET DIAGNOSTICS CONDITION 1 p_error_message = MESSAGE_TEXT;
          ROLLBACK;
        END;

        START TRANSACTION;

        UPDATE ORDERS
        SET `status` = p_new_status, updated_at = CURRENT_TIMESTAMP
        WHERE order_id = p_order_id;

        IF NOT EXISTS (SELECT 1 FROM ORDER_ITEMS WHERE order_id = p_order_id FOR UPDATE) THEN
          ROLLBACK;
          SET p_error_message = CONCAT('No items found for order: ', p_order_id);
          LEAVE attempt;
        END IF;

        IF p_new_status IN ('PAID', 'SHIPPED') THEN
          UPDATE DIAMONDS d
          JOIN ORDER_ITEMS oi ON oi.diamond_id = d.diamond_id
          SET d.`status` = 'SOLD', d.updated_at = CURRENT_TIMESTAMP
          WHERE oi.order_id = p_order_id;
        ELSEIF p_new_status = 'CANCELLED' THEN
          UPDATE DIAMONDS d
          JOIN ORDER_ITEMS oi ON oi.diamond_id = d.diamond_id
          SET d.`status` = 'AVAILABLE', d.updated_at = CURRENT_TIMESTAMP
          WHERE oi.order_id = p_order_id;
        END IF;

        COMMIT;
        SET p_success = TRUE;
      END attempt;

      IF p_success OR NOT v_retry THEN
        LEAVE retry_loop;
      END IF;
      IF v_attempt > v_max_retries THEN
        SET p_error_message = 'Max retries exceeded for order fulfillment';
        LEAVE retry_loop;
      END IF;
      DO SLEEP(0.1 * v_attempt);
    END LOOP;
  END IF;

END$$

-- ========================================================================
-- Bulk Create Daily Inventory Snapshot
-- ========================================================================
-- Purpose: Create daily inventory snapshot for reporting
-- Lock order: DIAMONDS (consistent read) -> INVENTORY_SNAPSHOT
-- ========================================================================
CREATE PROCEDURE sp_create_inventory_snapshot(
  IN p_snapshot_date DATE,
  OUT p_success TINYINT(1),
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_retry TINYINT(1);

  SET p_success = FALSE;
  SET p_error_message = '';

  IF p_snapshot_date IS NULL THEN
    SET p_snapshot_date = CURRENT_DATE();
  END IF;

  IF EXISTS (SELECT 1 FROM INVENTORY_SNAPSHOT WHERE snapshot_date = p_snapshot_date) THEN
    SET p_error_message = CONCAT('Snapshot already exists for date: ', p_snapshot_date);
  ELSE
    retry_loop: LOOP
      SET v_attempt = v_attempt + 1;
      SET v_retry = FALSE;

      attempt: BEGIN
        DECLARE EXIT HANDLER FOR SQLSTATE '40001', 1205 BEGIN
          ROLLBACK;
          SET v_retry = TRUE;
        END;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
          GET DIAGNOSTICS CONDITION 1 p_error_message = MESSAGE_TEXT;
          ROLLBACK;
        END;

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
          COALESCE(SUM(d.`status` = 'AVAILABLE'), 0) AS total_available,
          COALESCE(SUM(d.`status` = 'RESERVED'), 0) AS total_reserved,
          COALESCE(SUM(d.`status` = 'SOLD'), 0) AS total_sold,
          COALESCE(SUM(d.price_usd), 0) AS total_value_usd,
          (SELECT COALESCE(SUM(rs.cost_usd), 0)
             FROM ROUGH_STONES rs
            WHERE rs.rough_id IN (SELECT rough_id FROM DIAMONDS)) AS total_cost_usd
        FROM DIAMONDS d;

        COMMIT;
        SET p_success = TRUE;
      END attempt;

      IF p_success OR NOT v_retry THEN
        LEAVE retry_loop;
      END IF;
      IF v_attempt > v_max_retries THEN
        SET p_error_message = 'Max retries exceeded for snapshot creation';
        LEAVE retry_loop;
      END IF;
      DO SLEEP(0.1 * v_attempt);
    END LOOP;
  END IF;

END$$

DELIMITER ;
