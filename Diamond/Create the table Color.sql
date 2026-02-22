#Create the table Color
CREATE TABLE COLOR (
Grade CHAR(1) PRIMARY KEY CHECK (Grade BETWEEN "D" AND "Z"),
multiplier DECIMAL (6,3) NOT NULL CHECK (multiplier>0)
) ENGINE=InnoDB;