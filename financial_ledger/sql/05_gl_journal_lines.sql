-- GL Lines
CREATE TABLE IF NOT EXISTS core.gl_journal_lines (
line_id BIGINT AUTO_INCREMENT PRIMARY KEY,
journal_id BIGINT NOT NULL,
line_no INT NOT NULL, 
account_id BIGINT NOT NULL,
debit_amount DECIMAL(18,2) NULL,
credit_amount DECIMAL(18,2) NULL, 
memo VARCHAR(500) NULL,
CONSTRAINT fk_gll_header
  FOREIGN KEY (journal_id) REFERENCES core.gl_journal_header(journal_id)
  ON UPDATE RESTRICT ON DELETE CASCADE,
CONSTRAINT fk_gll_account
  FOREIGN KEY (account_id) REFERENCES core.chart_of_accounts(account_id)
  ON UPDATE RESTRICT ON DELETE RESTRICT,
CONSTRAINT ck_gll_single_sided CHECK(
  (debit_amount IS NULL) <> (credit_amount IS NULL)
),
CONSTRAINT ck_gll_non_negative CHECK (
  coalesce(debit_amount, 0) >= 0 AND coalesce(credit_amount, 0) >= 0
),
UNIQUE KEY uq_gll_journal_line (journal_id, line_no),
KEY ix_gll_account (account_id),
KEY ix_gll_journal (journal_id)
) ENGINE=InnoDB;