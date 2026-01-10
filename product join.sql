SELECT DISTINCT v1.product_name, v1.list_price
FROM products v1 JOIN products v2
    ON v1.list_price = v2.list_price AND
       v1.product_id <> v2.product_id
       
ORDER BY v1.product_name;