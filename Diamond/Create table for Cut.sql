# Create table for Cut
CREATE TABLE CUT (
Grade ENUM("Excellent", "Very Good", "Good", "Fair", "Poor") PRIMARY KEY,
multiplier DECIMAL(6,3) NOT NULL CHECK (multiplier>0)
) ENGINE=InnoDB