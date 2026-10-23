-- ========================================================================
-- Reporting Views
-- ========================================================================
-- Run after 02_reference_data.sql. Grade ordering uses grade_rank from the
-- GIA reference tables (1 = best), never alphabetical order.
-- ========================================================================

USE Diamond_company;

-- Full GIA 4Cs profile of every diamond, with grade ranges and carat band
CREATE OR REPLACE VIEW v_diamond_4c AS
SELECT
  d.diamond_id,
  d.sku,
  d.carat,
  cb.band_name AS carat_band,
  d.cut_grade,
  cu.grade_rank AS cut_rank,
  d.color_grade,
  co.category AS color_category,
  co.grade_rank AS color_rank,
  d.clarity_grade,
  cl.category AS clarity_category,
  cl.grade_rank AS clarity_rank,
  d.price_usd,
  ROUND(d.price_usd / d.carat, 2) AS price_per_carat,
  d.certified,
  d.certification_number,
  d.status
FROM DIAMONDS d
LEFT JOIN CUT cu ON cu.Grade = d.cut_grade
JOIN COLOR co ON co.Grade = d.color_grade
JOIN CLARITY cl ON cl.Grade = d.clarity_grade
LEFT JOIN CARAT_BAND cb ON d.carat BETWEEN cb.min_carat AND cb.max_carat;

-- Public catalog of available diamonds with 4C fields
CREATE OR REPLACE VIEW v_diamond_catalog AS
SELECT
  diamond_id, sku, carat, carat_band, cut_grade, color_grade, color_category,
  clarity_grade, clarity_category, price_usd, certified
FROM v_diamond_4c
WHERE status = "AVAILABLE";

-- Sales by month summary
CREATE OR REPLACE VIEW v_sales_by_month AS
SELECT
  DATE_FORMAT(o.order_date, "%Y-%m-01") AS month_start,
  COUNT(DISTINCT o.order_id) AS orders_count,
  SUM(oi.price_at_sale * oi.quantity) AS total_revenue
FROM ORDERS o
JOIN ORDER_ITEMS oi ON oi.order_id = o.order_id
WHERE o.status IN ("PAID", "SHIPPED")
GROUP BY DATE_FORMAT(o.order_date, "%Y-%m-01");

-- Grading distribution across the 4Cs
CREATE OR REPLACE VIEW v_grading_distribution AS
SELECT
  carat_band, cut_grade, color_grade, clarity_grade,
  COUNT(*) AS stones,
  ROUND(AVG(price_usd), 2) AS avg_price_usd
FROM v_diamond_4c
GROUP BY carat_band, cut_grade, color_grade, clarity_grade;

-- Inventory valuation
CREATE OR REPLACE VIEW v_inventory_value AS
SELECT
  COUNT(*) AS total_available,
  COALESCE(SUM(price_usd), 0) AS total_value_usd
FROM DIAMONDS
WHERE status = "AVAILABLE";
