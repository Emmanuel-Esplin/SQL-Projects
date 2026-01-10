INSERT INTO products 
	( category_id, product_code, product_name, description, list_price, discount_percent, 
    date_added)
VALUES 
	( 4, 'dgx_640', 'Yamaha DGX 640 88-Key Digital Piano', 
    'Long description to come.', 799.99, 0, '2025-08-01 18:58'
);

select * from my_guitar_shop.products
where product_code = 'dgx_640';