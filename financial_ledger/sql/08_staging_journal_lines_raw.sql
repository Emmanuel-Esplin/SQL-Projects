-- Raw Journal line from CSV
CREATE TABLE IF NOT EXISTS staging.journal_lines_raw (
source_file VARCHAR(255),
row_num INT,
reference TEXT, -- ties to header reference
line_no TEXT,
account_code TEXT,
debit_amount TEXT,
credit_amount TEXT,
memo TEXT,
loaded_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
row_hash VARBINARY(32),
UNIQUE KEY uq_jl_row (source_file, row_num),
KEY ix_jl_ref (reference(100))
) ENGINE=InnoDB;