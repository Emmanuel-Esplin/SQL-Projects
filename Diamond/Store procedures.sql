USE Diamond_company;

DELIMITER $$

#Compute price
CREATE PROCEDURE sp_compute_price(IN p_diamond_id INT)
BEGIN
DECLARE v_carat DECIMAL(5, 2);
DECLARE v_cut ENUM("Excellent", "Very Good", "Good", "Fair", "Poor");
DECLARE v_color CHAR(1);
DECLARE v_clarity ENUM("FL", "IF", "VVS1", "VVS2", "VS1", "VS2", "SI1", "SI2", "I1", "I2", "I3");
DECLARE v_base DECIMAL(10, 2);
DECLARE v_m_cut DECIMAL(6, 3);
DECLARE v_m_color DECIMAL(6, 3);
DECLARE v_m_clarity DECIMAL(6, 3); 
DECLARE v_price DECIMAL(12, 2);

SELECT carat, cut_grade, color_grade, clarity_grade, base_price_per_carat
INTO v_carat, v_cut, v_color, v_clarity, v_base
FROM DIAMONDS WHERE diamond_id = p_diamond_id FOR UPDATE;

SELECT multiplier INTO v_m_cut FROM CUT WHERE grade = v_cut;
SELECT multiplier INTO v_m_color FROM COLOR WHERE grade = v_color;
SELECT multiplier INTO v_m_clarity FROM CLARITY WHERE grade = v_clarity;

SET v_price = round(v_carat * v_base * IFNULL(v_m_cut, 1) * IFNULL(v_m_color, 1) * IFNULL(v_m_clarity, 1), 2);
UPDATE DIAMONDS SET price_usd = v_price WHERE diamond_id = p_diamond_id;

END$$

#Grade a diamond 4Cs and recompute price
CREATE PROCEDURE sp_grade_diamond(
IN p_diamond_id INT,
IN p_cut ENUM("Excellent", "Very Godd", "Good", "Fair", "Poor"),
IN p_color CHAR(1),
IN p_clarity ENUM("FL", "IF", "VVS1", "VVS2", "VS1", "VS2", "SI1", "SI2", "I1", "I2", "I3")
)
BEGIN
UPDATE DIAMONDS
SET cut_grade = p_cut,
color_grade = p_color,
clarity_grade = p_clarity
WHERE diamond_id = p_diamond_id;

CALL sp_compute_price(p_diamond_id);
END$$

#Place an order and reserve a stone
CREATE PROCEDURE sp_place_order(
IN p_customer_id INT,
IN p_diamond_id INT,
OUT p_order_id INT
)
BEGIN
DECLARE v_status ENUM("AVAILABLE", "RESERVED", "SOLD");

START TRANSACTION;

SELECT status INTO v_status FROM DIAMONDS WHERE diamond_id = p_diamond_id FOR UPDATE;
IF v_status <> "AVAILABLE" THEN
SIGNAL SQLSTATE "45000" SET MESSAGE_TEXT = "Diamond not available";
END IF;

INSERT INTO ORDERS(customer_id, order_date, status)
VALUES(p_customer_id, current_date(), "PENDING");
SET p_order_id = last_insert_id();

INSERT INTO ORDER_Items(order_id, diamond_id, price_at_sale)
SELECT p_order_id, d.diamond_id, d.price_usd
FROM DIAMONDS d WHERE d.diamond_id = p_diamond_id;

UPDATE DIAMONDS SET status = "RESERVED" WHERE diamond_id = p_diamond_id;
COMMIT;
END$$

#Mark order as paid or shipped and update the diamond status 
CREATE PROCEDURE sp_fulfill_order(IN p_order_id INT, IN p_new_status ENUM("PAID", "SHIPPED", "CANCELLED"))
BEGIN
DECLARE v_diamond_id INT;

START TRANSACTION;
UPDATE ORDERS SET status = p_new_status WHERE order_id = p_order_id;

SELECT diamond_id INTO v_diamond_id FROM ORDER_Items WHERE order_id =p_order_id LIMIT 1 FOR UPDATE;

IF p_new_status IN ("PAID", "SHIPPED") THEN
UPDATE DIAMONDS SET status = "SOLD" WHERE diamond_id = v_diamond_id;
ELSEIF p_new_status = "CANCELLED" THEN
UPDATE DIAMONDS SET status = "AVAILABLE" WHERE diamond_id = v_diamond_id;
END IF;
COMMIT;
END$$
DELIMITER ;
