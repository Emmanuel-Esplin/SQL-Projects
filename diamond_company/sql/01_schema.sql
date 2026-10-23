-- ========================================================================
-- Diamond Company Database - Schema
-- ========================================================================
-- Run first. WARNING: drops and recreates Diamond_company (all data lost).
-- Grading follows the GIA 4Cs: Carat, Cut, Color, Clarity.
-- ========================================================================

DROP DATABASE IF EXISTS Diamond_company;
CREATE DATABASE IF NOT EXISTS Diamond_company
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE Diamond_company;

-- ========================================================================
-- 4Cs Reference Tables (no foreign keys - these are locked first)
-- grade_rank: 1 = best grade on the GIA scale
-- ========================================================================

CREATE TABLE CUT(
  Grade ENUM("Excellent", "Very Good", "Good", "Fair", "Poor") PRIMARY KEY COMMENT 'GIA Cut Grade',
  grade_rank TINYINT UNSIGNED NOT NULL UNIQUE COMMENT 'Position on GIA cut scale (1 = Excellent)',
  description VARCHAR(255) NOT NULL COMMENT 'GIA description of light performance',
  multiplier DECIMAL(6,3) NOT NULL CHECK (multiplier > 0) COMMENT 'Price multiplier for this cut'
) ENGINE=InnoDB
  COMMENT='GIA cut grades (standard round brilliant)';

CREATE TABLE COLOR(
  Grade CHAR(1) PRIMARY KEY COMMENT 'GIA Color Grade D-Z' CHECK (Grade BETWEEN 'D' AND 'Z'),
  grade_rank TINYINT UNSIGNED NOT NULL UNIQUE COMMENT 'Position on GIA color scale (1 = D)',
  category ENUM("Colorless", "Near Colorless", "Faint", "Very Light", "Light") NOT NULL COMMENT 'GIA color range',
  multiplier DECIMAL(6,3) NOT NULL CHECK (multiplier > 0) COMMENT 'Price multiplier for this color'
) ENGINE=InnoDB
  COMMENT='GIA color grades D (colorless) to Z (light yellow/brown)';

CREATE TABLE CLARITY(
  Grade ENUM("FL", "IF", "VVS1", "VVS2", "VS1", "VS2", "SI1", "SI2", "I1", "I2", "I3") PRIMARY KEY COMMENT 'GIA Clarity Grade',
  grade_rank TINYINT UNSIGNED NOT NULL UNIQUE COMMENT 'Position on GIA clarity scale (1 = FL)',
  category ENUM("Flawless", "Internally Flawless", "Very, Very Slightly Included",
                "Very Slightly Included", "Slightly Included", "Included") NOT NULL COMMENT 'GIA clarity category',
  multiplier DECIMAL(6,3) NOT NULL CHECK (multiplier > 0) COMMENT 'Price multiplier for this clarity'
) ENGINE=InnoDB
  COMMENT='GIA clarity grades FL to I3 (11 grades)';

-- Carat is measured, not graded: GIA reports weight to the hundredth of a carat.
-- Bands group weights for reporting (prices jump at "magic sizes" like 1.00 ct).
CREATE TABLE CARAT_BAND(
  band_name VARCHAR(20) PRIMARY KEY COMMENT 'Display label, e.g. 1.00-1.49 ct',
  min_carat DECIMAL(5,2) NOT NULL UNIQUE CHECK (min_carat >= 0) COMMENT 'Inclusive lower bound',
  max_carat DECIMAL(5,2) NOT NULL CHECK (max_carat > 0) COMMENT 'Inclusive upper bound',
  CHECK (max_carat > min_carat)
) ENGINE=InnoDB
  COMMENT='Carat weight bands for 4Cs reporting';

-- ========================================================================
-- Supplier and Employee Tables (independent, can be locked in any order)
-- ========================================================================

CREATE TABLE SUPPLIERS(
  supplier_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique supplier identifier',
  name VARCHAR(120) NOT NULL COMMENT 'Supplier company name',
  country VARCHAR(80) COMMENT 'Country of origin',
  contact_email VARCHAR(120) UNIQUE COMMENT 'Supplier contact email',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
  UNIQUE KEY uk_name_country (name, country)
) ENGINE=InnoDB 
  COMMENT='Diamond suppliers - independent table';

CREATE TABLE EMPLOYEES(
  employee_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique employee identifier',
  full_name VARCHAR(120) NOT NULL COMMENT 'Employee full name',
  role VARCHAR(60) NOT NULL COMMENT 'Job role (Polisher, Grader, etc.)',
  hire_date DATE NOT NULL COMMENT 'Hire date',
  is_active BOOLEAN NOT NULL DEFAULT TRUE COMMENT 'Whether employee is still active',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
  KEY idx_active_role (is_active, role)
) ENGINE=InnoDB 
  COMMENT='Employees - independent table';

CREATE TABLE CUSTOMERS(
  customer_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique customer identifier',
  full_name VARCHAR(120) NOT NULL COMMENT 'Customer full name',
  email VARCHAR(120) UNIQUE COMMENT 'Customer email address',
  phone VARCHAR(40) COMMENT 'Customer phone number',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
  KEY idx_email (email),
  KEY idx_created_at (created_at)
) ENGINE=InnoDB
  COMMENT='Customers - independent table';

-- App logins. Polishers link to their EMPLOYEES row so custody events
-- and work orders can name them. Passwords are argon2 hashes only.
CREATE TABLE APP_USERS(
  user_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique user identifier',
  username VARCHAR(60) NOT NULL UNIQUE COMMENT 'Login name',
  full_name VARCHAR(120) NOT NULL COMMENT 'Display name',
  password_hash VARCHAR(255) NOT NULL COMMENT 'argon2id hash - never plaintext',
  role ENUM("ADMIN", "SAFE_KEEPER", "POLISHER", "SALES") NOT NULL COMMENT 'Permission set',
  employee_id INT UNIQUE COMMENT 'Linked employee record (required for polishers)',
  is_active BOOLEAN NOT NULL DEFAULT TRUE COMMENT 'Inactive users cannot log in',
  last_login_at DATETIME COMMENT 'Most recent successful login',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
  CONSTRAINT fk_user_employee FOREIGN KEY (employee_id) REFERENCES EMPLOYEES(employee_id),
  CONSTRAINT ck_user_polisher_employee CHECK (role <> 'POLISHER' OR employee_id IS NOT NULL),
  KEY idx_role_active (role, is_active)
) ENGINE=InnoDB
  COMMENT='Web app users and roles';

-- ========================================================================
-- Rough Stones (depends on SUPPLIERS only)
-- ========================================================================

CREATE TABLE ROUGH_STONES(
  rough_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique rough stone identifier',
  supplier_id INT NOT NULL COMMENT 'Supplier of this rough stone',
  received_date DATE NOT NULL COMMENT 'Date received at facility',
  weight_carat DECIMAL(8,3) NOT NULL CHECK (weight_carat > 0) COMMENT 'Weight in carats',
  cost_usd DECIMAL(12,2) NOT NULL CHECK (cost_usd >= 0) COMMENT 'Cost paid to supplier',
  status ENUM("RECEIVED", "ASSIGNED", "CUT", "REJECTED") NOT NULL DEFAULT "RECEIVED" COMMENT 'Processing status',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
  CONSTRAINT fk_rough_supplier FOREIGN KEY (supplier_id) REFERENCES SUPPLIERS(supplier_id),
  KEY idx_status (status),
  KEY idx_received_date (received_date),
  KEY idx_supplier_status (supplier_id, status),
  KEY idx_created_at (created_at)
) ENGINE=InnoDB 
  COMMENT='Raw diamond stones from suppliers';

-- ========================================================================
-- Diamonds (depends on ROUGH_STONES and reference tables)
-- Every tracked physical stone, from unpolished rough to polished gem.
-- sku holds the unique tracking code printed on the QR label.
-- Critical table for deadlock prevention
-- ========================================================================

CREATE TABLE DIAMONDS(
  diamond_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique diamond identifier',
  sku VARCHAR(40) NOT NULL UNIQUE COMMENT 'Tracking code (e.g. DC-26-7K3M9Q) - globally unique',
  rough_id INT COMMENT 'Rough purchase lot this stone came from (NULL if bought polished)',
  parent_diamond_id INT COMMENT 'Stone this one was cut from (lineage)',
  shape ENUM("Round", "Princess", "Cushion", "Oval", "Emerald", "Pear", "Marquise",
             "Radiant", "Asscher", "Heart", "Other") NOT NULL COMMENT 'Shape / cutting style',
  origin ENUM("NATURAL", "LAB_GROWN") NOT NULL COMMENT 'Natural or laboratory-grown',
  color_type ENUM("WHITE", "FANCY") NOT NULL DEFAULT "WHITE" COMMENT 'WHITE = graded D-Z; FANCY = graded by hue and intensity',
  fancy_hue VARCHAR(40) COMMENT 'Fancy color hue, e.g. Yellow, Pink, Blue',
  fancy_intensity ENUM("Faint", "Very Light", "Light", "Fancy Light", "Fancy", "Fancy Intense",
                       "Fancy Vivid", "Fancy Deep", "Fancy Dark") COMMENT 'GIA fancy color intensity',
  polish_state ENUM("UNPOLISHED", "POLISHED") NOT NULL COMMENT 'Rough/unpolished or polished',
  carat DECIMAL(5,2) NOT NULL CHECK (carat > 0) COMMENT 'Current weight, to the hundredth of a carat',
  cut_grade ENUM("Excellent", "Very Good", "Good", "Fair", "Poor") COMMENT 'GIA cut grade (NULL until graded; GIA grades cut on round brilliants)',
  color_grade CHAR(1) CHECK(color_grade BETWEEN 'D' AND 'Z') COMMENT 'GIA color grade D-Z (white stones)',
  clarity_grade ENUM("FL", "IF", "VVS1", "VVS2", "VS1", "VS2", "SI1", "SI2", "I1", "I2", "I3") COMMENT 'GIA clarity grade',
  depth_pct DECIMAL(5,2) CHECK (depth_pct BETWEEN 0 AND 100) COMMENT 'Total depth as % of average diameter',
  table_pct DECIMAL(5,2) CHECK (table_pct BETWEEN 0 AND 100) COMMENT 'Table width as % of average diameter',
  length_mm DECIMAL(5,2) CHECK (length_mm >= 0) COMMENT 'Measurement: length (mm)',
  width_mm DECIMAL(5,2) CHECK (width_mm >= 0) COMMENT 'Measurement: width (mm)',
  depth_mm DECIMAL(5,2) CHECK (depth_mm >= 0) COMMENT 'Measurement: depth (mm)',
  status ENUM("AVAILABLE", "IN_POLISHING", "IN_REPAIR", "RESERVED", "SOLD", "SPLIT") NOT NULL DEFAULT "AVAILABLE"
    COMMENT 'AVAILABLE = in the safe; RESERVED = being sold; SPLIT = cut into child stones',
  base_price_per_carat DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (base_price_per_carat >= 0) COMMENT 'Base price per carat',
  price_usd DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (price_usd >= 0) COMMENT 'Final computed price = carat * base * cut_mult * color_mult * clarity_mult',
  certified BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Whether a lab certificate is on file',
  certification_number VARCHAR(64) COMMENT 'Latest certificate report number',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
  CONSTRAINT fk_d_rough FOREIGN KEY(rough_id) REFERENCES ROUGH_STONES(rough_id),
  CONSTRAINT fk_d_parent FOREIGN KEY(parent_diamond_id) REFERENCES DIAMONDS(diamond_id),
  CONSTRAINT fk_d_cut FOREIGN KEY(cut_grade) REFERENCES CUT(Grade),
  CONSTRAINT fk_d_color FOREIGN KEY(color_grade) REFERENCES COLOR(Grade),
  CONSTRAINT fk_d_clarity FOREIGN KEY(clarity_grade) REFERENCES CLARITY(Grade),
  -- Polished stones must carry a clarity grade
  CONSTRAINT ck_d_polished_clarity CHECK (polish_state = 'UNPOLISHED' OR clarity_grade IS NOT NULL),
  -- Polished white stones must carry a D-Z color grade
  CONSTRAINT ck_d_white_color CHECK (color_type = 'FANCY' OR polish_state = 'UNPOLISHED' OR color_grade IS NOT NULL),
  -- Fancy stones are described by hue + intensity, never by D-Z
  CONSTRAINT ck_d_fancy_color CHECK (color_type = 'WHITE' OR (fancy_hue IS NOT NULL AND color_grade IS NULL)),
  CONSTRAINT ck_d_white_no_hue CHECK (color_type = 'FANCY' OR (fancy_hue IS NULL AND fancy_intensity IS NULL)),
  KEY idx_status (status),
  KEY idx_sku (sku),
  KEY idx_rough_id (rough_id),
  KEY idx_parent (parent_diamond_id),
  KEY idx_shape_origin (shape, origin),
  KEY idx_polish_state (polish_state, status),
  KEY idx_color_grade (color_grade),
  KEY idx_clarity_grade (clarity_grade),
  KEY idx_cut_grade (cut_grade),
  KEY idx_price_range (price_usd),
  KEY idx_available_price (status, price_usd),
  KEY idx_created_at (created_at),
  KEY idx_status_created (status, created_at)
) ENGINE=InnoDB
  COMMENT='Tracked stones, unpolished and polished';

-- ========================================================================
-- Work Orders (depends on DIAMONDS, ROUGH_STONES and EMPLOYEES)
-- One row per polishing / repair / recut job handed to an employee.
-- ========================================================================

CREATE TABLE WORK_ORDERS(
  work_order_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique work order identifier',
  diamond_id INT COMMENT 'Stone being worked on',
  rough_id INT COMMENT 'Rough lot being worked on (lot-level jobs)',
  employee_id INT NOT NULL COMMENT 'Employee assigned to this work',
  work_type ENUM("POLISH", "REPAIR", "RECUT") NOT NULL DEFAULT "POLISH" COMMENT 'Kind of job',
  start_date DATE NOT NULL COMMENT 'Work start date',
  end_date DATE COMMENT 'Work completion date',
  status ENUM("OPEN", "IN_PROGRESS", "DONE", "CANCELLED") NOT NULL DEFAULT "OPEN" COMMENT 'Work order status',
  notes VARCHAR(500) COMMENT 'Job instructions or repair reason',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
  CONSTRAINT fk_wo_diamond FOREIGN KEY (diamond_id) REFERENCES DIAMONDS(diamond_id),
  CONSTRAINT fk_wo_rough FOREIGN KEY (rough_id) REFERENCES ROUGH_STONES(rough_id),
  CONSTRAINT fk_wo_emp FOREIGN KEY (employee_id) REFERENCES EMPLOYEES(employee_id),
  CONSTRAINT ck_wo_subject CHECK (diamond_id IS NOT NULL OR rough_id IS NOT NULL),
  KEY idx_status (status),
  KEY idx_diamond_status (diamond_id, status),
  KEY idx_rough_status (rough_id, status),
  KEY idx_employee_status (employee_id, status),
  KEY idx_created_at (created_at)
) ENGINE=InnoDB
  COMMENT='Work orders for cutting, polishing and repairing stones';

-- ========================================================================
-- Safe custody ledger (insert-only; triggers block UPDATE/DELETE)
-- Every movement of a stone out of or back into the safe.
-- ========================================================================

CREATE TABLE CUSTODY_EVENTS(
  event_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique custody event identifier',
  diamond_id INT NOT NULL COMMENT 'Stone that moved',
  event_type ENUM("CHECK_OUT", "CHECK_IN") NOT NULL COMMENT 'Out of the safe, or back into it',
  purpose ENUM("POLISHING", "REPAIR", "VIEWING", "SALE") NOT NULL COMMENT 'Why the stone left the safe',
  actor_user_id INT NOT NULL COMMENT 'App user who took the stone out / put it back',
  holder_employee_id INT COMMENT 'Employee holding the stone while it is out (e.g. polisher)',
  weight_carat DECIMAL(5,2) NOT NULL CHECK (weight_carat > 0) COMMENT 'Weight measured at this event',
  work_order_id INT COMMENT 'Work order opened or closed by this event',
  notes VARCHAR(500) COMMENT 'Free-text remarks',
  occurred_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When the movement happened',
  CONSTRAINT fk_ce_diamond FOREIGN KEY (diamond_id) REFERENCES DIAMONDS(diamond_id),
  CONSTRAINT fk_ce_actor FOREIGN KEY (actor_user_id) REFERENCES APP_USERS(user_id),
  CONSTRAINT fk_ce_holder FOREIGN KEY (holder_employee_id) REFERENCES EMPLOYEES(employee_id),
  CONSTRAINT fk_ce_work_order FOREIGN KEY (work_order_id) REFERENCES WORK_ORDERS(work_order_id),
  KEY idx_diamond_time (diamond_id, occurred_at),
  KEY idx_holder_time (holder_employee_id, occurred_at),
  KEY idx_actor_time (actor_user_id, occurred_at)
) ENGINE=InnoDB
  COMMENT='Safe check-out / check-in ledger';

-- ========================================================================
-- Weight history (rough weight, polished weight, every re-weigh)
-- ========================================================================

CREATE TABLE WEIGHT_LOG(
  weight_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique weighing identifier',
  diamond_id INT NOT NULL COMMENT 'Stone weighed',
  weight_carat DECIMAL(5,2) NOT NULL CHECK (weight_carat > 0) COMMENT 'Measured weight',
  polish_state ENUM("UNPOLISHED", "POLISHED") NOT NULL COMMENT 'State of the stone when weighed',
  reason ENUM("INTAKE", "CHECK_OUT", "CHECK_IN", "SPLIT", "CORRECTION") NOT NULL COMMENT 'Why it was weighed',
  recorded_by INT COMMENT 'App user who recorded the weight (NULL for bulk import)',
  recorded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When it was weighed',
  CONSTRAINT fk_wl_diamond FOREIGN KEY (diamond_id) REFERENCES DIAMONDS(diamond_id),
  CONSTRAINT fk_wl_user FOREIGN KEY (recorded_by) REFERENCES APP_USERS(user_id),
  KEY idx_diamond_time (diamond_id, recorded_at)
) ENGINE=InnoDB
  COMMENT='Weight history for each stone';

-- ========================================================================
-- Lab certificates for polished stones (file stored on disk by the app)
-- ========================================================================

CREATE TABLE CERTIFICATES(
  certificate_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique certificate identifier',
  diamond_id INT NOT NULL COMMENT 'Polished stone the certificate belongs to',
  lab VARCHAR(40) NOT NULL DEFAULT 'GIA' COMMENT 'Issuing laboratory',
  report_number VARCHAR(64) NOT NULL COMMENT 'Lab report number',
  issue_date DATE COMMENT 'Date printed on the report',
  stored_filename VARCHAR(100) NOT NULL UNIQUE COMMENT 'Random file name under storage/certificates',
  original_filename VARCHAR(255) NOT NULL COMMENT 'Name of the uploaded file',
  mime_type ENUM("application/pdf", "image/jpeg", "image/png") NOT NULL COMMENT 'Verified file type',
  sha256 CHAR(64) NOT NULL COMMENT 'Hash of the file contents (integrity check)',
  uploaded_by INT NOT NULL COMMENT 'App user who uploaded it',
  uploaded_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Upload timestamp',
  CONSTRAINT fk_cert_diamond FOREIGN KEY (diamond_id) REFERENCES DIAMONDS(diamond_id),
  CONSTRAINT fk_cert_user FOREIGN KEY (uploaded_by) REFERENCES APP_USERS(user_id),
  UNIQUE KEY uk_lab_report (lab, report_number),
  KEY idx_diamond (diamond_id)
) ENGINE=InnoDB
  COMMENT='Grading certificates for polished diamonds';

-- ========================================================================
-- Orders and Order Items
-- Locking order: Orders first, then Order_Items, then Diamonds
-- ========================================================================

CREATE TABLE ORDERS(
  order_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique order identifier',
  customer_id INT NOT NULL COMMENT 'Customer placing order',
  order_date DATE NOT NULL COMMENT 'Date order was placed',
  status ENUM("PENDING", "PAID", "SHIPPED", "CANCELLED") NOT NULL DEFAULT "PENDING" COMMENT 'Order status',
  total_amount DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0) COMMENT 'Total order amount',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
  CONSTRAINT fk_o_customer FOREIGN KEY (customer_id) REFERENCES CUSTOMERS(customer_id),
  KEY idx_customer_id (customer_id),
  KEY idx_status (status),
  KEY idx_order_date (order_date),
  KEY idx_customer_status (customer_id, status),
  KEY idx_created_at (created_at)
) ENGINE=InnoDB 
  COMMENT='Customer orders for diamonds';

CREATE TABLE ORDER_ITEMS(
  order_item_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique order item identifier',
  order_id INT NOT NULL COMMENT 'Reference to order',
  diamond_id INT NOT NULL COMMENT 'Reference to diamond being ordered',
  price_at_sale DECIMAL(12,2) NOT NULL CHECK (price_at_sale >= 0) COMMENT 'Price at time of sale',
  quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0) COMMENT 'Quantity (typically 1 for diamonds)',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
  CONSTRAINT fk_oi_order FOREIGN KEY (order_id) REFERENCES ORDERS(order_id) ON DELETE CASCADE,
  CONSTRAINT fk_oi_diamond FOREIGN KEY (diamond_id) REFERENCES DIAMONDS(diamond_id),
  UNIQUE KEY uk_order_diamond (order_id, diamond_id),
  KEY idx_diamond_id (diamond_id),
  KEY idx_order_id (order_id)
) ENGINE=InnoDB 
  COMMENT='Individual items in an order';

-- ========================================================================
-- Audit and Inventory Tracking Tables
-- ========================================================================

CREATE TABLE AUDIT_LOG(
  audit_id BIGINT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique audit log entry identifier',
  table_name VARCHAR(64) NOT NULL COMMENT 'Table name where change occurred',
  action ENUM("INSERT", "UPDATE", "DELETE") NOT NULL COMMENT 'Type of action performed',
  row_id INT NOT NULL COMMENT 'ID of the row affected',
  payload JSON COMMENT 'JSON containing old and new values',
  changed_by VARCHAR(128) COMMENT 'User or process that made the change',
  changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Timestamp of change',
  KEY idx_table_action (table_name, action),
  KEY idx_changed_at (changed_at),
  KEY idx_row_id (row_id)
) ENGINE=InnoDB 
  COMMENT='Audit trail for all data changes';

CREATE TABLE INVENTORY_SNAPSHOT(
  snapshot_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique snapshot identifier',
  snapshot_date DATE NOT NULL COMMENT 'Date of snapshot',
  total_available INT NOT NULL COMMENT 'Total diamonds available for sale',
  total_reserved INT NOT NULL COMMENT 'Total diamonds reserved',
  total_sold INT NOT NULL COMMENT 'Total diamonds sold',
  total_value_usd DECIMAL(14,2) NOT NULL COMMENT 'Total inventory value in USD',
  total_cost_usd DECIMAL(14,2) NOT NULL COMMENT 'Total cost basis in USD',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'When snapshot was taken',
  UNIQUE KEY uk_date (snapshot_date),
  KEY idx_created_at (created_at)
) ENGINE=InnoDB 
  COMMENT='Daily inventory snapshots for reporting';

-- ========================================================================
-- Set proper transaction isolation level
-- ========================================================================
-- Note: This should be set at connection level in application code
-- For session: SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
