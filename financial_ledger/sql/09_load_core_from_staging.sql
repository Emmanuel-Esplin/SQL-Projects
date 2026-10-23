-- Upsert CoA from staging
INSERT INTO core.chart_of_accounts (account_code, account_name, account_type, natural_side)
SELECT DISTINCT
  trim(s.account_code), trim(s.account_name),
  upper(trim(s.account_type)), upper(trim(s.natural_side))
FROM staging.coa_raw s
LEFT JOIN core.chart_of_accounts c ON c.account_code = trim(s.account_code)
WHERE c.account_id IS NULL;

-- Map parents
UPDATE core.chart_of_accounts c
JOIN staging.coa_raw s ON c.account_code = trim(s.account_code)
LEFT JOIN core.chart_of_accounts p ON p.account_code = trim(s.parent_account_code)
SET c.parent_account_id = p.account_id
WHERE s.parent_account_code IS NOT NULL;

-- Ensure periods exist from staging headers (YYYYMM key)
INSERT IGNORE INTO core.financial_periods (period_id, period_name, start_date, end_date, is_closed)
SELECT
  cast(replace(trim(period_name), '-', '') AS UNSIGNED) AS period_id,
  trim(period_name),
  str_to_date(concat(trim(period_name), '-01'), '%Y-%m-%d') AS start_date, 
  LAST_DAY(str_to_date(concat(trim(period_name), '-01'), '%Y-%m-%d')) AS end_date,
0
FROM staging.journal_header_raw;  