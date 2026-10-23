-- ========================================================================
-- Sample Data
-- ========================================================================
-- Small demo dataset. Run last (after 02_reference_data.sql and the
-- procedures), so triggers validate the rows and prices are computed.
-- ========================================================================

USE Diamond_company;

INSERT INTO SUPPLIERS(name, country, contact_email) VALUES
("Botswana Minerals", "Botswana", "contact@bm.example");

INSERT INTO EMPLOYEES(full_name, role, hire_date) VALUES
("Master Polisher A", "Polisher", "2023-01-10");

INSERT INTO ROUGH_STONES(supplier_id, received_date, weight_carat, cost_usd, status) VALUES
(1, "2025-05-10", 4.200, 9500, "RECEIVED");

INSERT INTO WORK_ORDERS(rough_id, employee_id, start_date, status) VALUES
(1, 1, "2025-05-12", "IN_PROGRESS");

INSERT INTO DIAMONDS(sku, rough_id, carat, cut_grade, color_grade, clarity_grade, base_price_per_carat, certified, certification_number) VALUES
("SKU-0001", 1, 1.20, "Excellent", "G", "VS1", 6000, TRUE, "GIA-SAMPLE-0001"),
("SKU-0002", 1, 0.90, "Very Good", "H", "SI1", 4500, TRUE, "GIA-SAMPLE-0002");

-- Price both stones from their 4Cs
CALL sp_compute_price(1, @ok, @err);
CALL sp_compute_price(2, @ok, @err);

INSERT INTO CUSTOMERS(full_name, email, phone) VALUES
("Alpha Client", "client@ao.example", "+1-555-0100");

INSERT INTO ORDERS(customer_id, order_date, status) VALUES
(1, CURRENT_DATE(), "PENDING");
