SELECT c.category_name, 
       COUNT(p.product_id) AS product_count,
       MAX(p.list_price) AS highest_price
FROM categories c
JOIN products p ON c.category_id = p.category_id
GROUP BY c.category_name
ORDER BY product_count DESC;