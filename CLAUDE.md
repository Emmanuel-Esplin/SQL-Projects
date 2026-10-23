# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

A portfolio of standalone SQL learning projects. There is no build system, test suite, or linter. Scripts are run by hand in a SQL client. Each top-level folder is independent, and each targets a specific engine:

| Folder | Engine | Nature |
|---|---|---|
| `diamond_company/` | MySQL 8.0+ (InnoDB, utf8mb4) | The main project: GIA 4Cs schema, procedures, triggers, views, CSV import |
| `financial_ledger/` | MySQL 8.0+ | General ledger split across `staging` → `core` → `mart` schemas |
| `mysql_exercises/` | MySQL | Textbook exercises, mostly against `my_guitar_shop`; `ecommerce_schema.sql` creates `my_web_db` |
| `postgresql_exercises/` | PostgreSQL | Data types and `COPY` exercises using CSVs in `data/` |

Use the dialect of the folder you're in. `ENUM`, `AUTO_INCREMENT`, `DELIMITER $$` and `SIGNAL SQLSTATE '45000'` are MySQL; `COPY`, `bigserial` and `GENERATED ... AS IDENTITY` are PostgreSQL.

## Conventions

- File and folder names are `snake_case` with no spaces. Scripts that must run in order get numeric prefixes (`01_`, `02_`, …). Keep these conventions for new files and renumber when you insert a step.
- Never commit credentials or machine-specific absolute paths. Use `-p` or `mysql_config_editor` in docs, and paths relative to the project folder in scripts.
- Generated data (`diamond_company/data/processed/`) is gitignored. Commit the raw source data only.

## Diamond project

### Deploy and test

Run from `diamond_company/`:

```bash
for f in sql/0*.sql; do mysql -u <user> -p < "$f"; done      # 01 DROPs and recreates Diamond_company
python3 scripts/transform_to_gia.py                            # data/raw -> data/processed
mysql --local-infile=1 -u <user> -p Diamond_company < scripts/load_diamonds.sql
```

There are no automated tests. To verify a change, deploy all scripts to a throwaway MySQL instance, run the import, and `CALL` the procedures, including their failure paths (bad grade, missing row, diamond already reserved). Expected import result: 53,942 imported, 0 rejected. A second run imports 0.

### Architecture

- **GIA 4Cs.** `CUT`, `COLOR` (all of D–Z) and `CLARITY` use the grade as the primary key and carry `grade_rank` (1 = best), `category` and a price `multiplier`. `CARAT_BAND` groups measured carat weight into ranges; it has no foreign key. `DIAMONDS` has a foreign key to each grade table. Carat is `DECIMAL(5,2)` because GIA reports weight to the hundredth. Order grades by `grade_rank`, never alphabetically. Price = carat × base_price_per_carat × the three multipliers (`sp_compute_price`).
- **Flow.** `SUPPLIERS` → `ROUGH_STONES` → `WORK_ORDERS` (with `EMPLOYEES`) → `DIAMONDS` → `ORDERS`/`ORDER_ITEMS` (with `CUSTOMERS`). `AUDIT_LOG` holds JSON entries written by the triggers. `INVENTORY_SNAPSHOT` holds daily totals.
- **Procedure pattern.** Every write procedure returns `p_success` and `p_error_message` OUT parameters. Each attempt runs inside an `attempt: BEGIN … END` block with EXIT handlers. On SQLSTATE `40001` or error 1205, the procedure rolls back and retries, at most 3 times, sleeping 0.1 s × attempt. Any other `SQLEXCEPTION` rolls back and stops (`GET DIAGNOSTICS` fills the message). A business-rule failure rolls back and `LEAVE attempt`s. New procedures must follow this pattern; do not use CONTINUE handlers for errors.
- **Lock order.** Reference tables → `ROUGH_STONES` → `WORK_ORDERS` → `ORDERS` → `DIAMONDS` → `ORDER_ITEMS` → `AUDIT_LOG`.
- **Triggers** compare old and new values with `<=>`, because `cut_grade` and `certification_number` can be NULL. Triggers cannot call procedures, so a 4C change only writes a `price_update_needed` entry to the audit log.
- **Import.** MySQL forbids `LOAD DATA` inside stored programs, so the import runs in two steps. First, `scripts/load_diamonds.sql` loads the CSV on the client into `stg_diamonds_import`, using a path relative to `diamond_company/`. Then `sp_import_diamonds` validates rows by joining them to the reference tables, skips SKUs that already exist, and derives `base_price_per_carat` so that repricing reproduces the CSV price.
- **Cut mapping.** The raw Kaggle cut names are mapped in `transform_to_gia.py`: Ideal → Excellent, Premium → Very Good.

## Financial project

Each file in `financial_ledger/sql/` creates one object, and the numeric prefixes give the run order. Staging tables store every CSV field as `TEXT` plus `source_file`, `row_num` and `row_hash`. `09_load_core_from_staging.sql` trims and casts staging rows into `core`, then links each account to its parent in a second pass. In MySQL a "schema" is a database, so `core.chart_of_accounts` is a cross-database reference.
