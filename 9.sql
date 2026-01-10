DELIMITER //
CREATE PROCEDURE insert_category(IN cat_name VARCHAR(255))
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
        SELECT 'Insert failed: category may already exist.' AS message;

    INSERT INTO categories (category_name)
    VALUES (cat_name);
END;
//
DELIMITER ;

-- Test 1: should succeed
CALL insert_category('Digital Drums');

-- Test 2: should fail if category already exists
CALL insert_category('Digital Drums');

SELECT * FROM my_guitar_shop.categories
WHERE category_name = 'Digital Drums';