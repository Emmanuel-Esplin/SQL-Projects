-- ========================================================================
-- Sample Data
-- ========================================================================
-- Small demo dataset. Run last (after 02_reference_data.sql and the
-- procedures), so triggers validate the rows and prices are computed.
-- Creates no app users or passwords: run app/scripts/create_admin.py.
-- ========================================================================

USE Diamond_company;

INSERT INTO SUPPLIERS(name, country, contact_email) VALUES
("Botswana Minerals", "Botswana", "contact@bm.example");

INSERT INTO EMPLOYEES(full_name, role, hire_date) VALUES
("Master Polisher A", "Polisher", "2023-01-10"),
("Polisher B", "Polisher", "2024-03-04"),
("Safe Keeper C", "Safe Keeper", "2022-08-15");

INSERT INTO ROUGH_STONES(supplier_id, received_date, weight_carat, cost_usd, status) VALUES
(1, "2025-05-10", 4.200, 9500, "RECEIVED");

-- sp_register_diamond(actor, rough, parent, shape, origin, color_type, fancy_hue, fancy_intensity,
--                     polish_state, carat, cut, color, clarity, price_usd, base_price_per_carat, ...)

-- Polished white rounds, priced from base price x 4C multipliers
CALL sp_register_diamond(NULL, 1, NULL, "Round", "NATURAL", "WHITE", NULL, NULL,
                         "POLISHED", 1.20, "Excellent", "G", "VS1", NULL, 6000, @id, @sku, @ok, @err);
CALL sp_register_diamond(NULL, 1, NULL, "Round", "NATURAL", "WHITE", NULL, NULL,
                         "POLISHED", 0.90, "Very Good", "H", "SI1", NULL, 4500, @id, @sku, @ok, @err);

-- Fancy pink (graded by hue + intensity, priced manually)
CALL sp_register_diamond(NULL, NULL, NULL, "Cushion", "NATURAL", "FANCY", "Pink", "Fancy Intense",
                         "POLISHED", 0.75, NULL, NULL, "VS2", 48000, NULL, @id, @sku, @ok, @err);

-- Lab-grown oval
CALL sp_register_diamond(NULL, NULL, NULL, "Oval", "LAB_GROWN", "WHITE", NULL, NULL,
                         "POLISHED", 1.50, NULL, "E", "VVS2", 2400, NULL, @id, @sku, @ok, @err);

-- Unpolished rough from the Botswana lot, waiting to be split or polished
CALL sp_register_diamond(NULL, 1, NULL, "Other", "NATURAL", "WHITE", NULL, NULL,
                         "UNPOLISHED", 2.10, NULL, NULL, NULL, NULL, NULL, @id, @sku, @ok, @err);

INSERT INTO CUSTOMERS(full_name, email, phone) VALUES
("Alpha Client", "client@ao.example", "+1-555-0100");

INSERT INTO ORDERS(customer_id, order_date, status) VALUES
(1, CURRENT_DATE(), "PENDING");
