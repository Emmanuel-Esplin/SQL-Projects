-- ========================================================================
-- Reporting Views
-- ========================================================================
-- Run after 02_reference_data.sql. Grade ordering uses grade_rank from the
-- GIA reference tables (1 = best), never alphabetical order.
-- ========================================================================

USE Diamond_company;

-- Full profile of every stone: type, GIA 4Cs with grade ranges, carat band.
-- Color and clarity are LEFT JOINs: fancy and unpolished stones may have no
-- D-Z color or clarity grade.
CREATE OR REPLACE VIEW v_diamond_4c AS
SELECT
  d.diamond_id,
  d.sku,
  d.shape,
  d.origin,
  d.color_type,
  d.fancy_hue,
  d.fancy_intensity,
  d.polish_state,
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
  d.parent_diamond_id,
  d.rough_id,
  d.status
FROM DIAMONDS d
LEFT JOIN CUT cu ON cu.Grade = d.cut_grade
LEFT JOIN COLOR co ON co.Grade = d.color_grade
LEFT JOIN CLARITY cl ON cl.Grade = d.clarity_grade
LEFT JOIN CARAT_BAND cb ON d.carat BETWEEN cb.min_carat AND cb.max_carat;

-- Public catalog: polished diamonds in stock
CREATE OR REPLACE VIEW v_diamond_catalog AS
SELECT
  diamond_id, sku, shape, origin, color_type, fancy_hue, fancy_intensity,
  carat, carat_band, cut_grade, color_grade, color_category,
  clarity_grade, clarity_category, price_usd, certified
FROM v_diamond_4c
WHERE status = "AVAILABLE" AND polish_state = "POLISHED";

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

-- Grading distribution across the 4Cs (polished stones)
CREATE OR REPLACE VIEW v_grading_distribution AS
SELECT
  carat_band, cut_grade, color_grade, clarity_grade,
  COUNT(*) AS stones,
  ROUND(AVG(price_usd), 2) AS avg_price_usd
FROM v_diamond_4c
WHERE polish_state = "POLISHED"
GROUP BY carat_band, cut_grade, color_grade, clarity_grade;

-- Inventory valuation
CREATE OR REPLACE VIEW v_inventory_value AS
SELECT
  COUNT(*) AS total_available,
  COALESCE(SUM(price_usd), 0) AS total_value_usd
FROM DIAMONDS
WHERE status = "AVAILABLE";

-- Stones per status and polish state (dashboard tiles)
CREATE OR REPLACE VIEW v_status_summary AS
SELECT
  status,
  polish_state,
  COUNT(*) AS stones,
  COALESCE(SUM(carat), 0) AS total_carat,
  COALESCE(SUM(price_usd), 0) AS total_value_usd
FROM DIAMONDS
GROUP BY status, polish_state;

-- Stones currently out of the safe: the latest custody event is CHECK_OUT.
-- A SOLD stone that left for SALE has been delivered, so it is not listed.
-- Overdue: viewing/sale out for more than 1 day, polishing/repair for
-- more than 14 days.
CREATE OR REPLACE VIEW v_stones_out_of_safe AS
WITH last_event AS (
  SELECT ce.*,
         ROW_NUMBER() OVER (PARTITION BY ce.diamond_id ORDER BY ce.event_id DESC) AS rn
  FROM CUSTODY_EVENTS ce
)
SELECT
  d.diamond_id,
  d.sku,
  d.shape,
  d.polish_state,
  d.status,
  le.purpose,
  le.weight_carat AS weight_out,
  le.occurred_at AS out_since,
  TIMESTAMPDIFF(HOUR, le.occurred_at, NOW()) AS hours_out,
  le.holder_employee_id,
  e.full_name AS holder_name,
  le.actor_user_id AS released_by_user_id,
  u.full_name AS released_by,
  le.work_order_id,
  (
    (le.purpose IN ('VIEWING', 'SALE') AND le.occurred_at < NOW() - INTERVAL 1 DAY)
    OR (le.purpose IN ('POLISHING', 'REPAIR') AND le.occurred_at < NOW() - INTERVAL 14 DAY)
  ) AS is_overdue
FROM last_event le
JOIN DIAMONDS d ON d.diamond_id = le.diamond_id
JOIN APP_USERS u ON u.user_id = le.actor_user_id
LEFT JOIN EMPLOYEES e ON e.employee_id = le.holder_employee_id
WHERE le.rn = 1 AND le.event_type = 'CHECK_OUT'
  AND NOT (le.purpose = 'SALE' AND d.status = 'SOLD');

-- Weight in vs out for every work order (polishing loss, repair loss)
CREATE OR REPLACE VIEW v_work_order_weights AS
SELECT
  wo.work_order_id,
  wo.diamond_id,
  d.sku,
  wo.employee_id,
  e.full_name AS employee_name,
  wo.work_type,
  wo.status,
  wo.start_date,
  wo.end_date,
  co.weight_carat AS weight_out,
  ci.weight_carat AS weight_in,
  co.weight_carat - ci.weight_carat AS weight_removed,
  co.actor_user_id AS released_by_user_id,
  ci.actor_user_id AS returned_by_user_id
FROM WORK_ORDERS wo
JOIN EMPLOYEES e ON e.employee_id = wo.employee_id
LEFT JOIN DIAMONDS d ON d.diamond_id = wo.diamond_id
LEFT JOIN CUSTODY_EVENTS co ON co.work_order_id = wo.work_order_id AND co.event_type = 'CHECK_OUT'
LEFT JOIN CUSTODY_EVENTS ci ON ci.work_order_id = wo.work_order_id AND ci.event_type = 'CHECK_IN';

-- Polisher workload: open jobs, completed jobs, carats removed
CREATE OR REPLACE VIEW v_polisher_workload AS
SELECT
  e.employee_id,
  e.full_name,
  e.role,
  COALESCE(SUM(w.status IN ('OPEN', 'IN_PROGRESS')), 0) AS open_jobs,
  COALESCE(SUM(w.status = 'DONE'), 0) AS completed_jobs,
  COALESCE(SUM(CASE WHEN w.status = 'DONE' THEN w.weight_removed END), 0) AS carat_removed
FROM EMPLOYEES e
LEFT JOIN v_work_order_weights w ON w.employee_id = e.employee_id
WHERE e.is_active
GROUP BY e.employee_id, e.full_name, e.role;

-- Lineage: every stone with its root ancestor, depth and code path.
-- For one family, filter by root_diamond_id.
CREATE OR REPLACE VIEW v_diamond_lineage AS
WITH RECURSIVE tree AS (
  SELECT diamond_id, diamond_id AS root_diamond_id, 0 AS depth,
         CAST(sku AS CHAR(1000)) AS lineage_path
  FROM DIAMONDS
  WHERE parent_diamond_id IS NULL
  UNION ALL
  SELECT d.diamond_id, t.root_diamond_id, t.depth + 1,
         CONCAT(t.lineage_path, ' > ', d.sku)
  FROM DIAMONDS d
  JOIN tree t ON d.parent_diamond_id = t.diamond_id
)
SELECT diamond_id, root_diamond_id, depth, lineage_path FROM tree;
