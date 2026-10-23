-- Chart of Accounts
CREATE TABLE IF NOT EXISTS core.chart_of_accounts (
  account_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  account_code VARCHAR(50) NOT NULL UNIQUE,
  account_name VARCHAR(255) NOT NULL,
  account_type ENUM("ASSET", "LIABILITY", "EQUITY", "REVENUE", "EXPENSE") NOT NULL,
  parent_account_id BIGINT NULL,
  is_active TINYINT NOT NULL DEFAULT 1,
  natural_side ENUM ("DEBIT", "CREDIT") NOT NULL,
CONSTRAINT fk_coa_parent
   FOREIGN KEY (parent_account_id)
   REFERENCES core.chart_of_accounts(account_id)
   ON UPDATE RESTRICT ON DELETE RESTRICT
) ENGINE=InnoDB;