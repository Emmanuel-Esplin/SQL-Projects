-- General Ledger journal header
CREATE TABLE IF NOT EXISTS core.gl_journal_header (
journal_id BIGINT AUTO_INCREMENT PRIMARY KEY,
period_id INT NOT NULL,
journal_date DATE NOT NULL,
source VARCHAR(50) NOT NULL,
reference VARCHAR(100) NOT NULL, 
description VARCHAR(500) NULL,
posted_by VARCHAR(100) NOT NULL,
posted_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
CONSTRAINT fk_glh_period
  FOREIGN KEY (period_id) 
  REFERENCES core.financial_periods(period_id)
  ON UPDATE RESTRICT ON DELETE RESTRICT,
UNIQUE KEY uq_glh_period_reference (period_id, reference),
KEY ix_glh_period_date(period_id, journal_date)
) ENGINE=InnoDB;