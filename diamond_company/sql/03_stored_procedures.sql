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
DROP PROCEDURE IF EXISTS sp_register_diamond;
DROP PROCEDURE IF EXISTS sp_check_out_diamond;
DROP PROCEDURE IF EXISTS sp_check_in_diamond;
DROP PROCEDURE IF EXISTS sp_split_diamond;
DROP PROCEDURE IF EXISTS sp_add_certificate;
DROP FUNCTION IF EXISTS fn_new_tracking_code;

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
  DECLARE v_polish_state VARCHAR(20);
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
        SELECT `status`, polish_state, price_usd INTO v_status, v_polish_state, v_price
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

        IF v_polish_state <> 'POLISHED' THEN
          ROLLBACK;
          SET p_error_message = 'Only polished diamonds can be sold';
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

-- ========================================================================
-- Tracking code generator
-- ========================================================================
-- Format: DC-<yy>-<6 chars of Crockford base32> e.g. DC-26-7K3M9Q.
-- Crockford base32 omits I, L, O and U so codes are easy to read aloud
-- and hard to mistype. 32^6 = ~1 billion codes per year.
-- ========================================================================
CREATE FUNCTION fn_new_tracking_code()
RETURNS VARCHAR(40)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
  DECLARE v_alphabet CHAR(32) DEFAULT '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  DECLARE v_code VARCHAR(40);
  DECLARE v_i INT;
  DECLARE v_tries INT DEFAULT 0;

  REPEAT
    SET v_code = CONCAT('DC-', DATE_FORMAT(CURRENT_DATE(), '%y'), '-');
    SET v_i = 0;
    WHILE v_i < 6 DO
      -- 256 is a multiple of 32, so each character is uniformly random
      SET v_code = CONCAT(v_code, SUBSTRING(v_alphabet, 1 + (ORD(RANDOM_BYTES(1)) % 32), 1));
      SET v_i = v_i + 1;
    END WHILE;
    SET v_tries = v_tries + 1;
  UNTIL v_tries >= 10 OR NOT EXISTS (SELECT 1 FROM DIAMONDS WHERE sku = v_code) END REPEAT;

  RETURN v_code;
END$$

-- ========================================================================
-- Register a stone (intake into the safe)
-- ========================================================================
-- Price: pass p_price_usd to set it manually (base_price_per_carat is then
-- derived), or leave it NULL to compute it from p_base_price_per_carat and
-- the 4C multipliers. Grades not given use a multiplier of 1.0.
-- Writes the first WEIGHT_LOG row (reason INTAKE).
-- ========================================================================
CREATE PROCEDURE sp_register_diamond(
  IN p_actor_user_id INT,
  IN p_rough_id INT,
  IN p_parent_diamond_id INT,
  IN p_shape VARCHAR(20),
  IN p_origin VARCHAR(20),
  IN p_color_type VARCHAR(10),
  IN p_fancy_hue VARCHAR(40),
  IN p_fancy_intensity VARCHAR(20),
  IN p_polish_state VARCHAR(20),
  IN p_carat DECIMAL(5,2),
  IN p_cut VARCHAR(20),
  IN p_color CHAR(1),
  IN p_clarity VARCHAR(10),
  IN p_price_usd DECIMAL(12,2),
  IN p_base_price_per_carat DECIMAL(10,2),
  OUT p_diamond_id INT,
  OUT p_sku VARCHAR(40),
  OUT p_success TINYINT(1),
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_mult DECIMAL(12,6);
  DECLARE v_base DECIMAL(10,2);
  DECLARE v_price DECIMAL(12,2);
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_retry TINYINT(1);

  SET p_diamond_id = 0;
  SET p_sku = NULL;
  SET p_success = FALSE;
  SET p_error_message = '';

  IF p_carat IS NULL OR p_carat <= 0 THEN
    SET p_error_message = 'Weight must be greater than 0 ct';
  ELSEIF p_price_usd < 0 OR p_base_price_per_carat < 0 THEN
    SET p_error_message = 'Price cannot be negative';
  ELSEIF p_parent_diamond_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM DIAMONDS WHERE diamond_id = p_parent_diamond_id) THEN
    SET p_error_message = CONCAT('Parent stone not found: ', p_parent_diamond_id);
  ELSE
    -- Combined 4C multiplier
    SET v_mult = COALESCE((SELECT multiplier FROM CUT WHERE Grade = p_cut), 1)
               * COALESCE((SELECT multiplier FROM COLOR WHERE Grade = UPPER(p_color)), 1)
               * COALESCE((SELECT multiplier FROM CLARITY WHERE Grade = UPPER(p_clarity)), 1);

    IF p_price_usd IS NOT NULL THEN
      SET v_price = p_price_usd;
      SET v_base = ROUND(p_price_usd / (p_carat * v_mult), 2);
    ELSE
      SET v_base = COALESCE(p_base_price_per_carat, 0);
      SET v_price = ROUND(p_carat * v_base * v_mult, 2);
    END IF;

    retry_loop: LOOP
      SET v_attempt = v_attempt + 1;
      SET v_retry = FALSE;

      attempt: BEGIN
        DECLARE EXIT HANDLER FOR SQLSTATE '40001', 1205 BEGIN
          ROLLBACK;
          SET v_retry = TRUE;
          SET p_diamond_id = 0, p_sku = NULL;
        END;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
          GET DIAGNOSTICS CONDITION 1 p_error_message = MESSAGE_TEXT;
          ROLLBACK;
          SET p_diamond_id = 0, p_sku = NULL;
        END;

        START TRANSACTION;

        SET p_sku = fn_new_tracking_code();

        INSERT INTO DIAMONDS (
          sku, rough_id, parent_diamond_id, shape, origin, color_type, fancy_hue, fancy_intensity,
          polish_state, carat, cut_grade, color_grade, clarity_grade,
          base_price_per_carat, price_usd, `status`
        ) VALUES (
          p_sku, p_rough_id, p_parent_diamond_id, p_shape, p_origin, p_color_type, p_fancy_hue, p_fancy_intensity,
          p_polish_state, p_carat, p_cut, UPPER(p_color), UPPER(p_clarity),
          v_base, v_price, 'AVAILABLE'
        );
        SET p_diamond_id = LAST_INSERT_ID();

        INSERT INTO WEIGHT_LOG (diamond_id, weight_carat, polish_state, reason, recorded_by)
        VALUES (p_diamond_id, p_carat, p_polish_state, 'INTAKE', p_actor_user_id);

        COMMIT;
        SET p_success = TRUE;
      END attempt;

      IF p_success OR NOT v_retry THEN
        LEAVE retry_loop;
      END IF;
      IF v_attempt > v_max_retries THEN
        SET p_error_message = 'Max retries exceeded for diamond registration';
        LEAVE retry_loop;
      END IF;
      DO SLEEP(0.1 * v_attempt);
    END LOOP;
  END IF;

END$$

-- ========================================================================
-- Check a stone OUT of the safe
-- ========================================================================
-- The stone must be in the safe (its last custody event is not CHECK_OUT)
-- and weigh what the record says (+/- 0.01 ct) before it is released.
-- POLISHING / REPAIR need an active employee to hold the stone; they open
-- a work order and move the stone to IN_POLISHING / IN_REPAIR.
-- VIEWING / SALE leave the status unchanged (the ledger shows it is out).
-- SALE is also how a SOLD stone is handed to its buyer: it is never
-- checked back in, and v_stones_out_of_safe stops listing it.
-- Lock order: DIAMONDS (FOR UPDATE) -> WORK_ORDERS -> CUSTODY_EVENTS -> WEIGHT_LOG
-- ========================================================================
CREATE PROCEDURE sp_check_out_diamond(
  IN p_diamond_id INT,
  IN p_purpose VARCHAR(20),
  IN p_holder_employee_id INT,
  IN p_weight_carat DECIMAL(5,2),
  IN p_actor_user_id INT,
  IN p_notes VARCHAR(500),
  OUT p_work_order_id INT,
  OUT p_success TINYINT(1),
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_carat DECIMAL(5,2);
  DECLARE v_polish_state VARCHAR(20);
  DECLARE v_last_event VARCHAR(20);
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_retry TINYINT(1);

  SET p_work_order_id = NULL;
  SET p_success = FALSE;
  SET p_error_message = '';

  IF p_purpose IS NULL OR p_purpose NOT IN ('POLISHING', 'REPAIR', 'VIEWING', 'SALE') THEN
    SET p_error_message = CONCAT('Invalid purpose: ', IFNULL(p_purpose, 'NULL'));
  ELSEIF p_weight_carat IS NULL OR p_weight_carat <= 0 THEN
    SET p_error_message = 'Weigh the stone before it leaves the safe';
  ELSEIF p_purpose IN ('POLISHING', 'REPAIR') AND p_holder_employee_id IS NULL THEN
    SET p_error_message = 'Choose the employee who will hold the stone';
  ELSEIF p_holder_employee_id IS NOT NULL AND NOT EXISTS (
           SELECT 1 FROM EMPLOYEES WHERE employee_id = p_holder_employee_id AND is_active) THEN
    SET p_error_message = 'Holder must be an active employee';
  ELSE
    retry_loop: LOOP
      SET v_attempt = v_attempt + 1;
      SET v_retry = FALSE;

      attempt: BEGIN
        DECLARE EXIT HANDLER FOR SQLSTATE '40001', 1205 BEGIN
          ROLLBACK;
          SET v_retry = TRUE;
          SET p_work_order_id = NULL;
        END;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
          GET DIAGNOSTICS CONDITION 1 p_error_message = MESSAGE_TEXT;
          ROLLBACK;
          SET p_work_order_id = NULL;
        END;
        DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

        SET v_status = NULL, v_last_event = NULL;
        START TRANSACTION;

        SELECT `status`, carat, polish_state INTO v_status, v_carat, v_polish_state
        FROM DIAMONDS
        WHERE diamond_id = p_diamond_id
        FOR UPDATE;

        IF v_status IS NULL THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Diamond not found: ', p_diamond_id);
          LEAVE attempt;
        END IF;

        SELECT event_type INTO v_last_event
        FROM CUSTODY_EVENTS
        WHERE diamond_id = p_diamond_id
        ORDER BY event_id DESC
        LIMIT 1;

        IF v_last_event = 'CHECK_OUT' THEN
          ROLLBACK;
          SET p_error_message = 'Stone is already out of the safe';
          LEAVE attempt;
        END IF;

        IF p_purpose IN ('POLISHING', 'REPAIR') AND v_status <> 'AVAILABLE' THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Only stones in stock can go for ', LOWER(p_purpose), '. Status: ', v_status);
          LEAVE attempt;
        END IF;

        -- A sold stone may only leave the safe to be handed to its buyer
        IF (p_purpose = 'VIEWING' AND v_status NOT IN ('AVAILABLE', 'RESERVED'))
           OR (p_purpose = 'SALE' AND v_status NOT IN ('AVAILABLE', 'RESERVED', 'SOLD')) THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Stone cannot leave the safe for ', LOWER(p_purpose), '. Status: ', v_status);
          LEAVE attempt;
        END IF;

        IF ABS(p_weight_carat - v_carat) > 0.01 THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Weight mismatch: record says ', v_carat, ' ct, scale reads ',
                                       p_weight_carat, ' ct. Re-weigh before release.');
          LEAVE attempt;
        END IF;

        IF p_purpose IN ('POLISHING', 'REPAIR') THEN
          INSERT INTO WORK_ORDERS (diamond_id, employee_id, work_type, start_date, `status`, notes)
          VALUES (p_diamond_id, p_holder_employee_id,
                  IF(p_purpose = 'POLISHING', 'POLISH', 'REPAIR'),
                  CURRENT_DATE(), 'IN_PROGRESS', p_notes);
          SET p_work_order_id = LAST_INSERT_ID();

          UPDATE DIAMONDS
          SET `status` = IF(p_purpose = 'POLISHING', 'IN_POLISHING', 'IN_REPAIR'),
              updated_at = CURRENT_TIMESTAMP
          WHERE diamond_id = p_diamond_id;
        END IF;

        INSERT INTO CUSTODY_EVENTS (diamond_id, event_type, purpose, actor_user_id,
                                    holder_employee_id, weight_carat, work_order_id, notes)
        VALUES (p_diamond_id, 'CHECK_OUT', p_purpose, p_actor_user_id,
                p_holder_employee_id, p_weight_carat, p_work_order_id, p_notes);

        INSERT INTO WEIGHT_LOG (diamond_id, weight_carat, polish_state, reason, recorded_by)
        VALUES (p_diamond_id, p_weight_carat, v_polish_state, 'CHECK_OUT', p_actor_user_id);

        COMMIT;
        SET p_success = TRUE;
      END attempt;

      IF p_success OR NOT v_retry THEN
        LEAVE retry_loop;
      END IF;
      IF v_attempt > v_max_retries THEN
        SET p_error_message = 'Max retries exceeded for check-out';
        LEAVE retry_loop;
      END IF;
      DO SLEEP(0.1 * v_attempt);
    END LOOP;
  END IF;

END$$

-- ========================================================================
-- Check a stone back IN to the safe
-- ========================================================================
-- Rejects a stone that comes back heavier (possible swap), or whose weight
-- changed during VIEWING / SALE. A polishing job may lose weight; the new
-- weight becomes the stone's carat, and p_weight_change returns the
-- difference (negative = weight removed).
-- p_mark_polished = TRUE (polishing jobs only) sets polish_state = POLISHED
-- and applies the GIA grades; polished stones must carry a clarity grade,
-- and white stones a D-Z color (enforced by CHECK constraints).
-- Lock order: DIAMONDS (FOR UPDATE) -> WORK_ORDERS -> CUSTODY_EVENTS -> WEIGHT_LOG
-- ========================================================================
CREATE PROCEDURE sp_check_in_diamond(
  IN p_diamond_id INT,
  IN p_weight_carat DECIMAL(5,2),
  IN p_actor_user_id INT,
  IN p_mark_polished TINYINT(1),
  IN p_cut VARCHAR(20),
  IN p_color CHAR(1),
  IN p_clarity VARCHAR(10),
  IN p_notes VARCHAR(500),
  OUT p_weight_change DECIMAL(5,2),
  OUT p_success TINYINT(1),
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_carat DECIMAL(5,2);
  DECLARE v_last_event VARCHAR(20);
  DECLARE v_purpose VARCHAR(20);
  DECLARE v_holder INT;
  DECLARE v_work_order_id INT;
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_retry TINYINT(1);

  SET p_weight_change = NULL;
  SET p_success = FALSE;
  SET p_error_message = '';
  SET p_mark_polished = IFNULL(p_mark_polished, FALSE);

  IF p_weight_carat IS NULL OR p_weight_carat <= 0 THEN
    SET p_error_message = 'Weigh the stone before it goes back into the safe';
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
        DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

        SET v_status = NULL, v_last_event = NULL;
        START TRANSACTION;

        SELECT `status`, carat INTO v_status, v_carat
        FROM DIAMONDS
        WHERE diamond_id = p_diamond_id
        FOR UPDATE;

        IF v_status IS NULL THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Diamond not found: ', p_diamond_id);
          LEAVE attempt;
        END IF;

        SELECT event_type, purpose, holder_employee_id, work_order_id
        INTO v_last_event, v_purpose, v_holder, v_work_order_id
        FROM CUSTODY_EVENTS
        WHERE diamond_id = p_diamond_id
        ORDER BY event_id DESC
        LIMIT 1;

        IF v_last_event IS NULL OR v_last_event <> 'CHECK_OUT' THEN
          ROLLBACK;
          SET p_error_message = 'Stone is not checked out of the safe';
          LEAVE attempt;
        END IF;

        IF p_weight_carat > v_carat + 0.01 THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Stone came back heavier (', v_carat, ' ct out, ', p_weight_carat,
                                       ' ct in). Possible swap - investigate before accepting.');
          LEAVE attempt;
        END IF;

        IF v_purpose IN ('VIEWING', 'SALE') AND ABS(p_weight_carat - v_carat) > 0.01 THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Weight changed while out for ', LOWER(v_purpose), ' (', v_carat, ' ct out, ',
                                       p_weight_carat, ' ct in). Possible swap - investigate before accepting.');
          LEAVE attempt;
        END IF;

        IF p_mark_polished AND v_purpose <> 'POLISHING' THEN
          ROLLBACK;
          SET p_error_message = 'Only a polishing job can mark a stone as polished';
          LEAVE attempt;
        END IF;

        SET p_weight_change = p_weight_carat - v_carat;

        IF v_purpose IN ('POLISHING', 'REPAIR') THEN
          UPDATE DIAMONDS
          SET carat = p_weight_carat,
              `status` = 'AVAILABLE',
              polish_state = IF(p_mark_polished, 'POLISHED', polish_state),
              cut_grade = IF(p_mark_polished, p_cut, cut_grade),
              color_grade = IF(p_mark_polished AND color_type = 'WHITE', UPPER(p_color), color_grade),
              clarity_grade = IF(p_mark_polished, UPPER(p_clarity), clarity_grade),
              updated_at = CURRENT_TIMESTAMP
          WHERE diamond_id = p_diamond_id;

          UPDATE WORK_ORDERS
          SET `status` = 'DONE', end_date = CURRENT_DATE()
          WHERE work_order_id = v_work_order_id;
        END IF;

        INSERT INTO CUSTODY_EVENTS (diamond_id, event_type, purpose, actor_user_id,
                                    holder_employee_id, weight_carat, work_order_id, notes)
        VALUES (p_diamond_id, 'CHECK_IN', v_purpose, p_actor_user_id,
                v_holder, p_weight_carat, v_work_order_id, p_notes);

        INSERT INTO WEIGHT_LOG (diamond_id, weight_carat, polish_state, reason, recorded_by)
        SELECT diamond_id, p_weight_carat, polish_state, 'CHECK_IN', p_actor_user_id
        FROM DIAMONDS WHERE diamond_id = p_diamond_id;

        COMMIT;
        SET p_success = TRUE;
      END attempt;

      IF p_success OR NOT v_retry THEN
        LEAVE retry_loop;
      END IF;
      IF v_attempt > v_max_retries THEN
        SET p_error_message = 'Max retries exceeded for check-in';
        LEAVE retry_loop;
      END IF;
      DO SLEEP(0.1 * v_attempt);
    END LOOP;
  END IF;

END$$

-- ========================================================================
-- Split a rough stone into child stones (lineage)
-- ========================================================================
-- p_child_weights: comma-separated carat weights, e.g. '1.20, 0.85'.
-- The parent must be unpolished, in stock and in the safe; the children
-- together cannot outweigh it. Children inherit the parent's lot, shape,
-- origin and color type; the parent becomes SPLIT.
-- p_child_skus returns the new tracking codes, comma-separated.
-- ========================================================================
CREATE PROCEDURE sp_split_diamond(
  IN p_parent_diamond_id INT,
  IN p_child_weights VARCHAR(500),
  IN p_actor_user_id INT,
  OUT p_child_skus VARCHAR(1000),
  OUT p_success TINYINT(1),
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_status VARCHAR(20);
  DECLARE v_carat DECIMAL(5,2);
  DECLARE v_polish_state VARCHAR(20);
  DECLARE v_last_event VARCHAR(20);
  DECLARE v_count INT;
  DECLARE v_i INT;
  DECLARE v_weight DECIMAL(5,2);
  DECLARE v_total DECIMAL(8,2);
  DECLARE v_sku VARCHAR(40);
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_retry TINYINT(1);

  SET p_child_skus = NULL;
  SET p_success = FALSE;
  SET p_error_message = '';

  IF p_child_weights IS NULL
     OR p_child_weights NOT REGEXP '^ *[0-9]+(\\.[0-9]{1,2})? *(, *[0-9]+(\\.[0-9]{1,2})? *)*$' THEN
    SET p_error_message = 'Enter child weights as numbers separated by commas, e.g. 1.20, 0.85';
  ELSE
    SET v_count = 1 + LENGTH(p_child_weights) - LENGTH(REPLACE(p_child_weights, ',', ''));
    SET v_total = 0, v_i = 1;
    WHILE v_i <= v_count DO
      SET v_weight = CAST(TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(p_child_weights, ',', v_i), ',', -1)) AS DECIMAL(5,2));
      IF v_weight <= 0 THEN
        SET p_error_message = 'Every child weight must be greater than 0 ct';
      END IF;
      SET v_total = v_total + v_weight;
      SET v_i = v_i + 1;
    END WHILE;
  END IF;

  IF p_error_message = '' THEN
    retry_loop: LOOP
      SET v_attempt = v_attempt + 1;
      SET v_retry = FALSE;

      attempt: BEGIN
        DECLARE EXIT HANDLER FOR SQLSTATE '40001', 1205 BEGIN
          ROLLBACK;
          SET v_retry = TRUE;
          SET p_child_skus = NULL;
        END;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
          GET DIAGNOSTICS CONDITION 1 p_error_message = MESSAGE_TEXT;
          ROLLBACK;
          SET p_child_skus = NULL;
        END;
        DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

        SET v_status = NULL, v_last_event = NULL, p_child_skus = NULL;
        START TRANSACTION;

        SELECT `status`, carat, polish_state INTO v_status, v_carat, v_polish_state
        FROM DIAMONDS
        WHERE diamond_id = p_parent_diamond_id
        FOR UPDATE;

        IF v_status IS NULL THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Diamond not found: ', p_parent_diamond_id);
          LEAVE attempt;
        END IF;

        SELECT event_type INTO v_last_event
        FROM CUSTODY_EVENTS
        WHERE diamond_id = p_parent_diamond_id
        ORDER BY event_id DESC
        LIMIT 1;

        IF v_status <> 'AVAILABLE' OR v_last_event = 'CHECK_OUT' THEN
          ROLLBACK;
          SET p_error_message = 'Only a stone that is in stock and in the safe can be split';
          LEAVE attempt;
        END IF;

        IF v_polish_state <> 'UNPOLISHED' THEN
          ROLLBACK;
          SET p_error_message = 'Only unpolished stones can be split';
          LEAVE attempt;
        END IF;

        IF v_total > v_carat THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Children weigh ', v_total, ' ct in total, more than the parent (', v_carat, ' ct)');
          LEAVE attempt;
        END IF;

        SET v_i = 1;
        WHILE v_i <= v_count DO
          SET v_weight = CAST(TRIM(SUBSTRING_INDEX(SUBSTRING_INDEX(p_child_weights, ',', v_i), ',', -1)) AS DECIMAL(5,2));
          SET v_sku = fn_new_tracking_code();

          INSERT INTO DIAMONDS (sku, rough_id, parent_diamond_id, shape, origin, color_type,
                                fancy_hue, fancy_intensity, polish_state, carat, `status`)
          SELECT v_sku, rough_id, diamond_id, shape, origin, color_type,
                 fancy_hue, fancy_intensity, 'UNPOLISHED', v_weight, 'AVAILABLE'
          FROM DIAMONDS WHERE diamond_id = p_parent_diamond_id;

          INSERT INTO WEIGHT_LOG (diamond_id, weight_carat, polish_state, reason, recorded_by)
          VALUES (LAST_INSERT_ID(), v_weight, 'UNPOLISHED', 'SPLIT', p_actor_user_id);

          SET p_child_skus = CONCAT_WS(',', p_child_skus, v_sku);
          SET v_i = v_i + 1;
        END WHILE;

        UPDATE DIAMONDS
        SET `status` = 'SPLIT', updated_at = CURRENT_TIMESTAMP
        WHERE diamond_id = p_parent_diamond_id;

        COMMIT;
        SET p_success = TRUE;
      END attempt;

      IF p_success OR NOT v_retry THEN
        LEAVE retry_loop;
      END IF;
      IF v_attempt > v_max_retries THEN
        SET p_error_message = 'Max retries exceeded for split';
        LEAVE retry_loop;
      END IF;
      DO SLEEP(0.1 * v_attempt);
    END LOOP;
  END IF;

END$$

-- ========================================================================
-- Record a lab certificate for a polished stone
-- ========================================================================
-- The app stores the file on disk first and passes its random file name
-- and sha256 here. Marks the stone certified with the report number.
-- ========================================================================
CREATE PROCEDURE sp_add_certificate(
  IN p_diamond_id INT,
  IN p_lab VARCHAR(40),
  IN p_report_number VARCHAR(64),
  IN p_issue_date DATE,
  IN p_stored_filename VARCHAR(100),
  IN p_original_filename VARCHAR(255),
  IN p_mime_type VARCHAR(40),
  IN p_sha256 CHAR(64),
  IN p_actor_user_id INT,
  OUT p_certificate_id INT,
  OUT p_success TINYINT(1),
  OUT p_error_message VARCHAR(255)
)
MODIFIES SQL DATA
BEGIN
  DECLARE v_polish_state VARCHAR(20);
  DECLARE v_attempt INT DEFAULT 0;
  DECLARE v_max_retries INT DEFAULT 3;
  DECLARE v_retry TINYINT(1);

  SET p_certificate_id = NULL;
  SET p_success = FALSE;
  SET p_error_message = '';

  IF p_report_number IS NULL OR TRIM(p_report_number) = '' THEN
    SET p_error_message = 'Enter the report number printed on the certificate';
  ELSEIF EXISTS (SELECT 1 FROM CERTIFICATES
                 WHERE lab = IFNULL(p_lab, 'GIA') AND report_number = TRIM(p_report_number)) THEN
    SET p_error_message = CONCAT(IFNULL(p_lab, 'GIA'), ' report ', TRIM(p_report_number), ' is already on file');
  ELSE
    retry_loop: LOOP
      SET v_attempt = v_attempt + 1;
      SET v_retry = FALSE;

      attempt: BEGIN
        DECLARE EXIT HANDLER FOR SQLSTATE '40001', 1205 BEGIN
          ROLLBACK;
          SET v_retry = TRUE;
          SET p_certificate_id = NULL;
        END;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN
          GET DIAGNOSTICS CONDITION 1 p_error_message = MESSAGE_TEXT;
          ROLLBACK;
          SET p_certificate_id = NULL;
        END;
        DECLARE CONTINUE HANDLER FOR NOT FOUND BEGIN END;

        SET v_polish_state = NULL;
        START TRANSACTION;

        SELECT polish_state INTO v_polish_state
        FROM DIAMONDS
        WHERE diamond_id = p_diamond_id
        FOR UPDATE;

        IF v_polish_state IS NULL THEN
          ROLLBACK;
          SET p_error_message = CONCAT('Diamond not found: ', p_diamond_id);
          LEAVE attempt;
        END IF;

        IF v_polish_state <> 'POLISHED' THEN
          ROLLBACK;
          SET p_error_message = 'Certificates can only be added to polished diamonds';
          LEAVE attempt;
        END IF;

        INSERT INTO CERTIFICATES (diamond_id, lab, report_number, issue_date, stored_filename,
                                  original_filename, mime_type, sha256, uploaded_by)
        VALUES (p_diamond_id, IFNULL(p_lab, 'GIA'), TRIM(p_report_number), p_issue_date, p_stored_filename,
                p_original_filename, p_mime_type, p_sha256, p_actor_user_id);
        SET p_certificate_id = LAST_INSERT_ID();

        UPDATE DIAMONDS
        SET certified = TRUE, certification_number = TRIM(p_report_number), updated_at = CURRENT_TIMESTAMP
        WHERE diamond_id = p_diamond_id;

        COMMIT;
        SET p_success = TRUE;
      END attempt;

      IF p_success OR NOT v_retry THEN
        LEAVE retry_loop;
      END IF;
      IF v_attempt > v_max_retries THEN
        SET p_error_message = 'Max retries exceeded for certificate upload';
        LEAVE retry_loop;
      END IF;
      DO SLEEP(0.1 * v_attempt);
    END LOOP;
  END IF;

END$$

DELIMITER ;
