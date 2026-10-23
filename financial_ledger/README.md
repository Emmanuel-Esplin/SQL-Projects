# Financial Ledger

A MySQL general-ledger model in three layers. The layers are separate MySQL databases, which MySQL calls schemas.

- **`staging`**: raw CSV rows, stored as `TEXT` with `source_file`, `row_num` and `row_hash` columns so the same file can be loaded twice safely.
- **`core`**: typed tables (financial periods, chart of accounts, journal headers and lines), protected by foreign keys and CHECK constraints. Each journal line is either a debit or a credit, never both, and amounts can't be negative.
- **`mart`**: reserved for reporting.

## Deploy

Run the scripts in numeric order:

```bash
for f in sql/0*.sql; do mysql -u <user> -p < "$f"; done
```

| Script | Creates |
|---|---|
| `01_schemas.sql` | `staging`, `core`, `mart` |
| `02`–`05` | `core.financial_periods`, `chart_of_accounts`, `gl_journal_header`, `gl_journal_lines` |
| `06`–`08` | `staging.coa_raw`, `journal_header_raw`, `journal_lines_raw` |
| `09_load_core_from_staging.sql` | Loads new accounts from staging, links each account to its parent, and creates any missing financial periods |
