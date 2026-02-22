USE Diamond_company;
DELIMITER $$

#Compute price automatically on insert/update of 4Cs/base
CREATE TRIGGER trg_diamonds_bi BEFORE INSERT ON DIAMONDS
FOR EACH ROW
BEGIN
#baisc sanity (Check also enforces carat/base >=0)
IF NEW.sku IS NULL OR NEW.sku = '' THEN
SET NEW.sku = CONCAT("SKU-", UUID());
END IF;

END$$

CREATE TRIGGER trg_diamond_au AFTER UPDATE ON DIAMONS
FOR EACH ROW
BEGIN
IF (OLD.carat <> NEW.carat 
  OR OLD.cut_grade <> New.cut_grade
  OR OLD.color_grade <> NEW.color_grade
  OR OLD.clarity_grade <> NEW.clarity_grade
  OR OLD.base_price_per_carat <> NEW.base_price_per_carat) THEN
CALL sp_compute_price(NEW.diamond_id);
END IF;

INSERT INTO AUDIT_LOG(table_name, action, row_id, payload)
VALUES ("DIAMONDS", "UPDATE", NEW.diamond_id, 
    JSON_OBJECT("old", JSON_OBJECT("price", OLD.price_usd, "status", OLD.status),
       "new", JSON_OBJECT("price", NEW.price_usd, "status", NEW.status)));
END$$

#Prevent duble-selling: when an order item is inserted, ensure diamond is available or reserved for this order
CREATE TRIGGER trg_order_items_bi BEFORE INSERT ON ORDER_Items
FOR EACH ROW
BEGIN
 DECLARE v_status ENUM("AVAILABLE", "RESERVED", "SOLD");
 SELECT status INTO v_status FROM DIAMONDS WHERE diamond_id = NEW.diamond_id FOR UPDATE;
 
 IF v_status ="SOLD" THEN
  SIGNAL SQLSTATE "45000" SET MESSAGE_TEXT = "Diamond already sold";
END IF;
END$$

DELIMITER;

