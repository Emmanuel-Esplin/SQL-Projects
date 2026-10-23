-- Financial periods
CREATE TABLE IF NOT EXISTS core.financial_periods (
period_id INT PRIMARY KEY, -- YYYYMM
period_name VARCHAR(20) NOT NULL, -- '2026-03'
start_date DATE NOT NULL,
end_date DATE NOT NULL,
is_closed TINYINT NOT NULL DEFAULT 0,
UNIQUE (period_name)
) ENGINE=InnoDB; 