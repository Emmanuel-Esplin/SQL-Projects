# Create database for Diamond company
DROP DATABASE IF EXISTS Diamond_company;
CREATE DATABASE IF NOT EXISTS Diamond_company CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE Diamond_company;

# Create table for Cut
CREATE TABLE CUT(
Grade ENUM("Execellent", "Very Good", "Good", "Fair", "Poor") PRIMARY KEY,
multiplier DECIMAL(6,3) NOT NULL CHECK (multiplier > 0)
) ENGINE=InnoDB;

# Create table for Color
CREATE TABLE COLOR(
Grade CHAR(1) PRIMARY KEY CHECK (Grade BETWEEN "D" AND "Z"),
multiplier DECIMAL(6,3) NOT NULL CHECK (multiplier > 0)
) ENGINE=InnoDB;

# Create table for Clarity
CREATE TABLE CLARITY(
Grade ENUM("FL", "IF", "VVS1", "VVS2", "VS1", "VS2", "SI1", "SI2", "I1", "I2", "I3") PRIMARY KEY,
multiplier DECIMAL(6,3) NOT NULL CHECK (multiplier > 0)
) ENGINE=InnoDB;

# Create table for Suppliers
CREATE TABLE SUPPLIERS(
supplier_id INT AUTO_INCREMENT PRIMARY KEY, 
name VARCHAR(120) NOT NULL,
country VARCHAR(80), 
contact_email VARCHAR(120)
) ENGINE=InnoDB;

# Create table for Employees
CREATE TABLE EMPLOYEES(
employee_id INT AUTO_INCREMENT PRIMARY KEY,
full_name VARCHAR(120) NOT NULL,
role VARCHAR(60) NOT NULL,
hire_date DATE NOT NULL
) ENGINE=InnoDB;

# Create table for Rough stones
CREATE TABLE ROUGH_STONES(
rough_id INT AUTO_INCREMENT PRIMARY KEY,
supplier_id INT NOT NULL,
received_date DATE NOT NULL,
weight_carat DECIMAL(8,3) NOT NULL CHECK (weight_carat > 0),
cost_usd DECIMAL(12,2) NOT NULL CHECK (cost_usd >= 0),
status ENUM("RECEIVED", "ASSIGNED", "CUT", "REJECTED") DEFAULT "RECEIVED",
CONSTRAINT fk_rough_supplier FOREIGN KEY (supplier_id) REFERENCES SUPPLIERS(supplier_id)
) ENGINE=InnoDB;

# Create table for Work orders
CREATE TABLE WORK_ORDERS(
work_order_id INT AUTO_INCREMENT PRIMARY KEY,
rough_id INT NOT NULL,
employee_id INT NOT NULL,
start_date DATE NOT NULL,
status ENUM("OPEN", "IN_PROGRESS", "DONE", "CANCELLED") DEFAULT "OPEN",
CONSTRAINT fk_wo_rough FOREIGN KEY (rough_id) REFERENCES ROUGH_STONES(rough_id),
CONSTRAINT fk_wo_emp FOREIGN KEY (employee_id) REFERENCES EMPLOYEES(employee_id)
) ENGINE=InnoDB;

# Create table for Diamonds 
CREATE TABLE DIAMONDS(
diamond_id INT AUTO_INCREMENT PRIMARY KEY,
sku VARCHAR(40) NOT NULL UNIQUE,
rough_id INT NOT NULL,
carat DECIMAL(5,2) NOT NULL CHECK (carat > 0),
cut_grade ENUM("Excellent", "Very Good", "Good", "Fair", "Poor") NULL,
color_grade CHAR(1) NOT NULL CHECK(color_grade BETWEEN "D" AND "Z"),
clarity_grade ENUM("FL", "IF", "VVS1", "VVS2", "VS1", "VS2", "SI1", "SI2", "I1", "I2", "I3") NOT NULL,
status ENUM("AVAILABLE", "RESERVED", "SOLD") DEFAULT "AVAILABLE",
base_price_per_carat DECIMAL(10,2) NOT NULL CHECK (base_price_per_carat >= 0),
price_usd DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (price_usd >= 0),
certified BOOLEAN DEFAULT FALSE,
certification_number VARCHAR(64),
created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
CONSTRAINT fk_d_rough FOREIGN KEY(rough_id) REFERENCES ROUGH_STONES(rough_id)
) ENGINE=InnoDB;

# Create table for Customers
CREATE TABLE CUSTOMERS(
customer_id INT AUTO_INCREMENT PRIMARY KEY,
full_name VARCHAR(120) NOT NULL, 
email VARCHAR(120) UNIQUE,
phone VARCHAR(40)
) ENGINE=InnoDB;

# Create table for Orders
CREATE TABLE ORDERS(
order_id INT AUTO_INCREMENT PRIMARY KEY,
customer_id INT NOT NULL,
order_date DATE NOT NULL,
status ENUM("PENDING", "PAID", "SHIPPED", "CANCELLED") DEFAULT "PENDING",
CONSTRAINT fk_o_customer FOREIGN KEY (customer_id) REFERENCES CUSTOMERS(customer_id)
) ENGINE=InnoDB;

# Create table for Ordered items
CREATE TABLE ORDER_Items(
order_item_id INT AUTO_INCREMENT PRIMARY KEY, 
order_id INT NOT NULL, 
diamond_id INT NOT NULL UNIQUE,
price_at_sale DECIMAL(12,2) NOT NULL CHECK (price_at_sale >= 0),
CONSTRAINT fk_oi_order FOREIGN KEY (order_id) REFERENCES ORDERS(order_id),
CONSTRAINT fk_oi_diamond FOREIGN KEY (diamond_id) REFERENCES DIAMONDS(diamond_id)
) ENGINE=InnoDB;

# Create table for JSON audit log
CREATE TABLE AUDIT_LOG(
audit_id BIGINT AUTO_INCREMENT PRIMARY KEY,
table_name VARCHAR(64) NOT NULL,
action ENUM("INSERT", "UPDATE", "DELETE") NOT NULL,
row_id INT NOT NULL, 
payload JSON,
changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

# Create table for inventory daily snapshots
CREATE TABLE INVENTORY_SNAPSHOT(
snapshot_date DATE NOT NULL,
total_available INT NOT NULL,
total_value_usd DECIMAL(14,2) NOT NULL,
PRIMARY KEY (snapshot_date)
) ENGINE=InnoDB;












