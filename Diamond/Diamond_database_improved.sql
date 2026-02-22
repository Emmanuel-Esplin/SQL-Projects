
DROP DATABASE IF EXISTS Diamond_company;
CREATE DATABASE IF NOT EXISTS Diamond_company 
  CHARACTER SET utf8mb4 
  COLLATE utf8mb4_0900_ai_ci;

USE Diamond_company;

-- ========================================================================
-- Reference Tables (no foreign keys - these are locked first)
-- ========================================================================

CREATE TABLE CUT(
  Grade ENUM("Excellent", "Very Good", "Good", "Fair", "Poor") PRIMARY KEY COMMENT 'GIA Cut Grade',
  multiplier DECIMAL(6,3) NOT NULL CHECK (multiplier > 0) COMMENT 'Price multiplier for this cut'
) ENGINE=InnoDB 
  COMMENT='Cut grades reference table - base reference';

CREATE TABLE COLOR(
  Grade CHAR(1) PRIMARY KEY COMMENT 'GIA Color Grade D-Z' CHECK (Grade BETWEEN 'D' AND 'Z'),
  multiplier DECIMAL(6,3) NOT NULL CHECK (multiplier > 0) COMMENT 'Price multiplier for this color'
) ENGINE=InnoDB 
  COMMENT='Color grades reference table - base reference';

CREATE TABLE CLARITY(
  Grade ENUM("FL", "IF", "VVS1", "VVS2", "VS1", "VS2", "SI1", "SI2", "I1", "I2", "I3") PRIMARY KEY COMMENT 'GIA Clarity Grade',
  multiplier DECIMAL(6,3) NOT NULL CHECK (multiplier > 0) COMMENT 'Price multiplier for this clarity'
) ENGINE=InnoDB 
  COMMENT='Clarity grades reference table - base reference';

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
-- Work Orders (depends on ROUGH_STONES and EMPLOYEES)
-- Locking order: ROUGH_STONES first, then EMPLOYEES
-- ========================================================================

CREATE TABLE WORK_ORDERS(
  work_order_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique work order identifier',
  rough_id INT NOT NULL COMMENT 'Reference to rough stone',
  employee_id INT NOT NULL COMMENT 'Employee assigned to this work',
  start_date DATE NOT NULL COMMENT 'Work start date',
  end_date DATE COMMENT 'Work completion date',
  status ENUM("OPEN", "IN_PROGRESS", "DONE", "CANCELLED") NOT NULL DEFAULT "OPEN" COMMENT 'Work order status',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
  CONSTRAINT fk_wo_rough FOREIGN KEY (rough_id) REFERENCES ROUGH_STONES(rough_id),
  CONSTRAINT fk_wo_emp FOREIGN KEY (employee_id) REFERENCES EMPLOYEES(employee_id),
  KEY idx_status (status),
  KEY idx_rough_id (rough_id),
  KEY idx_employee_id (employee_id),
  KEY idx_rough_status (rough_id, status),
  KEY idx_created_at (created_at),
  UNIQUE KEY uk_rough_pending (rough_id, status) COMMENT 'Ensure only one active work order per rough stone'
) ENGINE=InnoDB 
  COMMENT='Work orders for cutting and polishing stones';

-- ========================================================================
-- Diamonds (depends on ROUGH_STONES and reference tables)
-- Critical table for deadlock prevention
-- ========================================================================

CREATE TABLE DIAMONDS(
  diamond_id INT AUTO_INCREMENT PRIMARY KEY COMMENT 'Unique diamond identifier',
  sku VARCHAR(40) NOT NULL UNIQUE COMMENT 'Stock keeping unit - globally unique',
  rough_id INT NOT NULL COMMENT 'Reference to source rough stone',
  carat DECIMAL(5,2) NOT NULL CHECK (carat > 0) COMMENT 'Diamond weight in carats',
  cut_grade ENUM("Excellent", "Very Good", "Good", "Fair", "Poor") COMMENT 'GIA cut grade (nullable before grading)',
  color_grade CHAR(1) NOT NULL CHECK(color_grade BETWEEN 'D' AND 'Z') COMMENT 'GIA color grade D-Z',
  clarity_grade ENUM("FL", "IF", "VVS1", "VVS2", "VS1", "VS2", "SI1", "SI2", "I1", "I2", "I3") NOT NULL COMMENT 'GIA clarity grade',
  depth DECIMAL(5,2) COMMENT 'Depth percentage',
  table_pct DECIMAL(5,2) COMMENT 'Table percentage',
  status ENUM("AVAILABLE", "RESERVED", "SOLD") NOT NULL DEFAULT "AVAILABLE" COMMENT 'Availability status for ordering',
  base_price_per_carat DECIMAL(10,2) NOT NULL CHECK (base_price_per_carat >= 0) COMMENT 'Base price per carat',
  price_usd DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (price_usd >= 0) COMMENT 'Final computed price = carat * base * cut_mult * color_mult * clarity_mult',
  certified BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Whether certified by GIA',
  certification_number VARCHAR(64) COMMENT 'GIA certification number if certified',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Record creation timestamp',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT 'Last update timestamp',
  CONSTRAINT fk_d_rough FOREIGN KEY(rough_id) REFERENCES ROUGH_STONES(rough_id),
  CONSTRAINT fk_d_cut FOREIGN KEY(cut_grade) REFERENCES CUT(Grade),
  CONSTRAINT fk_d_color FOREIGN KEY(color_grade) REFERENCES COLOR(Grade),
  CONSTRAINT fk_d_clarity FOREIGN KEY(clarity_grade) REFERENCES CLARITY(Grade),
  KEY idx_status (status),
  KEY idx_sku (sku),
  KEY idx_rough_id (rough_id),
  KEY idx_color_grade (color_grade),
  KEY idx_clarity_grade (clarity_grade),
  KEY idx_cut_grade (cut_grade),
  KEY idx_price_range (price_usd),
  KEY idx_available_price (status, price_usd),
  KEY idx_created_at (created_at),
  KEY idx_status_created (status, created_at)
) ENGINE=InnoDB 
  COMMENT='Processed diamonds ready for sale';

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
-- Create indexes for non-existent foreign key references
-- ========================================================================

ALTER TABLE CUT ADD KEY idx_grade (Grade);
ALTER TABLE COLOR ADD KEY idx_grade (Grade);
ALTER TABLE CLARITY ADD KEY idx_grade (Grade);

-- ========================================================================
-- Set proper transaction isolation level
-- ========================================================================
-- Note: This should be set at connection level in application code
-- For session: SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;

COMMIT;
