-- Raw CoA from CSV
CREATE TABLE IF NOT EXISTS staging.coa_raw (
source_file VARCHAR(255),
row_num INT,
account_code TEXT,
account_name TEXT,
account_type TEXT,
parent_account_code TEXT,
natural_side TEXT,
loaded_side TEXT,
loaded_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
row_hash VARBINARY(32),
UNIQUE KEY uq_coa_row (source_file, row_num),
KEY ix_coa_hash (row_hash)
) ENGINE=InnoDB;