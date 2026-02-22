USE Diamond_company;

#Public catalog of available diamonds with 4C fields
CREATE OR REPLACE VIEW v_diamond_catalog AS
SELECT
d.diamond_id, d.sku, d.carat, d.cut_grade, d.color_grade, d.clarity_grade, d.price_usd, d.certified, d.status
FROM DIAMONDS d 
WHERE d.status = "AVAILABLE";

#Sales by month summary
CREATE OR REPLACE VIEW v_sales_by_month AS
SELECT
date_format(o.order_date, "%Y-%m-01") AS month_start,
COUNT(*)   AS orders_count,
SUM(oi.price_at_sale) AS total_revenue
FROM ORDERS o 
JOIN ORDER_Items oi ON oi.order_id = o.order_id
where o.status IN ("PAID", "SHIPPED")
GROUP BY date_format(o.order_date, "%Y-%m-01");

#Grading distribution snapshot
CREATE OR REPLACE VIEW v_grading_distribution AS
SELECT
d.cut_grade, d.color_grade, d.clarity_grade,
COUNT(*) AS stones
FROM DIAMONDS d 
GROUP BY d.cut_grade, d.color_grade, d.clarity_grade;

#Inventory valuation
CREATE OR REPLACE VIEW v_inventory_value AS
SELECT
COUNT(*) AS total_available,
SUM(price_usd) AS total_value_usd 
FROM DIAMONDS
WHERE status = "AVAILABLE";

