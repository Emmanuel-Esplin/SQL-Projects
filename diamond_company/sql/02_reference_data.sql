-- ========================================================================
-- GIA 4Cs Reference Data
-- ========================================================================
-- Seeds the complete GIA grading scales. Run after 01_schema.sql.
-- Multipliers are illustrative pricing factors used by sp_compute_price:
--   price_usd = carat * base_price_per_carat * cut_mult * color_mult * clarity_mult
-- ========================================================================

USE Diamond_company;

-- CUT: GIA cut grading scale for standard round brilliants (5 grades)
INSERT INTO CUT(Grade, grade_rank, description, multiplier) VALUES
("Excellent", 1, "Maximum brightness, fire and scintillation; even pattern", 1.20),
("Very Good", 2, "Strong brightness and fire; slightly less even than Excellent", 1.10),
("Good",      3, "Good brightness; noticeably less fire and scintillation", 1.00),
("Fair",      4, "Reduced brightness and fire; visible light leakage", 0.92),
("Poor",      5, "Dull appearance with little brightness or fire", 0.85);

-- COLOR: GIA D-to-Z scale (23 grades) grouped into the five GIA ranges
INSERT INTO COLOR(Grade, grade_rank, category, multiplier) VALUES
("D",  1, "Colorless",      1.30), ("E",  2, "Colorless",      1.25), ("F",  3, "Colorless",      1.20),
("G",  4, "Near Colorless", 1.15), ("H",  5, "Near Colorless", 1.10), ("I",  6, "Near Colorless", 1.05),
("J",  7, "Near Colorless", 1.00),
("K",  8, "Faint",          0.95), ("L",  9, "Faint",          0.92), ("M", 10, "Faint",          0.90),
("N", 11, "Very Light",     0.87), ("O", 12, "Very Light",     0.85), ("P", 13, "Very Light",     0.83),
("Q", 14, "Very Light",     0.81), ("R", 15, "Very Light",     0.79),
("S", 16, "Light",          0.77), ("T", 17, "Light",          0.75), ("U", 18, "Light",          0.73),
("V", 19, "Light",          0.71), ("W", 20, "Light",          0.69), ("X", 21, "Light",          0.67),
("Y", 22, "Light",          0.65), ("Z", 23, "Light",          0.63);

-- CLARITY: GIA clarity scale (11 grades in 6 categories)
INSERT INTO CLARITY(Grade, grade_rank, category, multiplier) VALUES
("FL",    1, "Flawless",                     1.55),
("IF",    2, "Internally Flawless",          1.45),
("VVS1",  3, "Very, Very Slightly Included", 1.35),
("VVS2",  4, "Very, Very Slightly Included", 1.30),
("VS1",   5, "Very Slightly Included",       1.20),
("VS2",   6, "Very Slightly Included",       1.15),
("SI1",   7, "Slightly Included",            1.00),
("SI2",   8, "Slightly Included",            0.92),
("I1",    9, "Included",                     0.80),
("I2",   10, "Included",                     0.70),
("I3",   11, "Included",                     0.60);

-- CARAT: reporting bands; bounds are inclusive at hundredth-of-a-carat precision
INSERT INTO CARAT_BAND(band_name, min_carat, max_carat) VALUES
("0.00-0.29 ct", 0.00,   0.29),
("0.30-0.49 ct", 0.30,   0.49),
("0.50-0.69 ct", 0.50,   0.69),
("0.70-0.89 ct", 0.70,   0.89),
("0.90-0.99 ct", 0.90,   0.99),
("1.00-1.49 ct", 1.00,   1.49),
("1.50-1.99 ct", 1.50,   1.99),
("2.00-2.99 ct", 2.00,   2.99),
("3.00-4.99 ct", 3.00,   4.99),
("5.00+ ct",     5.00, 999.99);
