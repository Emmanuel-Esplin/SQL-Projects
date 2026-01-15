""" Retrieve product code, name, list price, and discount percent for all products, ordered by list price in descending order """
SELECT product_code, product_name, list_price, discount_percent
FROM products
ORDER BY list_price DESC;