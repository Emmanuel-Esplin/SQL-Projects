-- Raw Journal header from CSV
CREATE TABLE IF NOT EXISTS staging.journal_header_raw (
source_file VARCHAR(255),
row_num INT,
period_name TEXT, -- "2026-03"
journal_date TEXT, -- "YYYY-MM-DD"
reference TEXT,
description TEXT,
posted_by TEXT,
loaded_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
row_hash VARBINARY(32),
UNIQUE KEY uq_jh_row (source_file, row_num),
KEY ix_jh_hash (row_hash)
) ENGINE=InnoDB;