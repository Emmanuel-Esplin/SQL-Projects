""" Create a view combining customer information with their billing and shipping addresses """
CREATE OR REPLACE VIEW customer_addresses AS
SELECT 
    c.customer_id, c.email_address, c.last_name, c.first_name,
    b.line1 AS bill_line1, b.line2 AS bill_line2, b.city AS bill_city,
    b.state AS bill_state, b.zip_code AS bill_zip,
    s.line1 AS ship_line1, s.line2 AS ship_line2, s.city AS ship_city,
    s.state AS ship_state, s.zip_code AS ship_zip
FROM customers c
JOIN addresses b ON c.billing_address_id = b.address_id
JOIN addresses s ON c.shipping_address_id = s.address_id;