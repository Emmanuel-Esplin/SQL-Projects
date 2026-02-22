INSERT INTO CUT VALUES
("Excellent", 1.20), ("Very Good", 1.10), ("Good", 1.00), ("Fair", 0.92), ("Poor", 0.85);

INSERT INTO COLOR (Grade, multiplier) VALUES
("D", 1.30), ("E", 1.25), ("F", 1.20), ("G", 1.15), ("H", 1.10), ("I", 1.05), ("J", 1.00), ("K", 0.95), ("L", 0.92), ("M", 0.90);

INSERT INTO CLARITY VALUES
("FL", 1.550), ("IF", 1.45), ("VVS1", 1.35), ("VVS2", 1.30), ("VS1", 1.20), ("VS2", 1.15), ("SI1", 1.00), ("SI2", 0.92), ("I1", 0.80), ("I2", 0.70), ("I3", 0.60);

INSERT INTO SUPPLIERS(name, country, contact_email) VALUES
("Botswana Minerals", "Botswana", "contact@bm.exapmle");

INSERT INTO EMPLOYEES(full_name, role, hire_date) VALUES
("Master Polisher A", "Polisher", "2023-01-10");

INSERT INTO ROUGH_STONES(supplier_id, received_date, weight_carat, cost_usd, status) VALUES
(1, "2025-05-10", 4.200, 9500, "RECEIVED");

INSERT INTO WORK_ORDERS(rough_id, employee_id, start_date, status) VALUES
(1, 1, "2025-05-12", "IN_PROGRESS");

INSERT INTO DIAMONDS(sku, rough_id, carat, cut_grade, color_grade, clarity_grade, base_price_per_carat, certified) VALUES
("SKU-0001", 1, 1.20, "Excellent", "G", "VS!", 6000, TRUE),
("SKU-0002", 1, 0.90, "Very Good", "H", "SI1", 4500, TRUE);

INSERT INTO CUSTOMERS(full_name, email, phone) VALUES
("Alpha Client", "client@ao.example", "+1-555-0100");

INSERT INTO ORDERS(customer_id, order_date, status) VALUES
(1, CURRENT_DATE(), "PENDING");
