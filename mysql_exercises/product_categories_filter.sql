""" Retrieve distinct category names from categories that have products listed in the Products table """
SELECT DISTINCT category_name
FROM categories
WHERE category_id IN (
    SELECT category_id FROM Products
)
ORDER BY category_name;