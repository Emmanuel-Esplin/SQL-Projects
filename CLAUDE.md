# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

A portfolio of standalone SQL learning projects. SQL scripts are run by hand in a SQL client; the only build or test tooling is the Diamond Tracker app's Python environment (`diamond_company/app/`). Each top-level folder is independent, and each targets a specific engine:

| Folder | Engine | Nature |
|---|---|---|
| `diamond_company/` | MySQL 8.0+ (InnoDB, utf8mb4) | The main project: GIA 4Cs schema, procedures, triggers, views, CSV import, plus the Diamond Tracker web app in `app/` |
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

For SQL changes, deploy all scripts to a throwaway MySQL instance, run the import, and `CALL` the procedures, including their failure paths (bad grade, missing row, diamond already reserved). Expected import result: 53,942 imported, 0 rejected. A second run imports 0.

The app's pytest suite (`diamond_company/app/tests/`) redeploys `sql/0*.sql`, which **drops `Diamond_company`**. It only runs with `DT_TEST_ALLOW_RESET=1`; never point it at a real database:

```bash
cd diamond_company/app
DT_TEST_DB_HOST=127.0.0.1 DT_TEST_DB_PORT=<port> DT_TEST_DB_USER=root DT_TEST_ALLOW_RESET=1 .venv/bin/pytest
.venv/bin/pytest tests/test_flow.py::test_full_lifecycle     # one test
```

### Architecture

- **GIA 4Cs.** `CUT`, `COLOR` (all of D–Z) and `CLARITY` use the grade as the primary key and carry `grade_rank` (1 = best), `category` and a price `multiplier`. `CARAT_BAND` groups measured carat weight into ranges; it has no foreign key. `DIAMONDS` has a foreign key to each grade table. Carat is `DECIMAL(5,2)` because GIA reports weight to the hundredth. Order grades by `grade_rank`, never alphabetically. Price = carat × base_price_per_carat × the three multipliers (`sp_compute_price`).
- **Stones.** `DIAMONDS` holds every tracked physical stone, rough or polished:
  - `polish_state` (UNPOLISHED/POLISHED), `shape`, `origin` (NATURAL/LAB_GROWN);
  - `color_type` WHITE (D–Z `color_grade`) or FANCY (`fancy_hue` + `fancy_intensity`);
  - `parent_diamond_id` for lineage (`sp_split_diamond`);
  - `sku`, the tracking code `DC-yy-XXXXXX`, from `fn_new_tracking_code()` (Crockford base32).

  CHECK constraints `ck_d_*` enforce what a polished or fancy stone must carry. `app/diamond_app/db.py` maps them to friendly messages, so keep the two in sync.
- **Statuses.** `status`: AVAILABLE (in the safe), IN_POLISHING, IN_REPAIR, RESERVED (being sold), SOLD, SPLIT.
- **Safe ledger.** "In the safe" is decided by the ledger, not by `status`: a stone is out when its latest `CUSTODY_EVENTS` row is CHECK_OUT (`v_stones_out_of_safe`). `CUSTODY_EVENTS` and `WEIGHT_LOG` are insert-only, enforced by triggers. Correct mistakes with new rows, never edits.
- **Flow.** `SUPPLIERS` → `ROUGH_STONES` → `DIAMONDS` → `WORK_ORDERS` / `CUSTODY_EVENTS` (with `EMPLOYEES`, `APP_USERS`) → `ORDERS`/`ORDER_ITEMS` (with `CUSTOMERS`). `AUDIT_LOG` holds JSON entries written by the triggers. `INVENTORY_SNAPSHOT` holds daily totals.
- **Procedure pattern.** Every write procedure returns `p_success` and `p_error_message` OUT parameters. Each attempt runs inside an `attempt: BEGIN … END` block with EXIT handlers. On SQLSTATE `40001` or error 1205, the procedure rolls back and retries, at most 3 times, sleeping 0.1 s × attempt. Any other `SQLEXCEPTION` rolls back and stops (`GET DIAGNOSTICS` fills the message). A business-rule failure rolls back and `LEAVE attempt`s. New procedures must follow this pattern; do not use CONTINUE handlers for errors.
- **Lock order.** Order and pricing procedures: reference tables → `ROUGH_STONES` → `ORDERS` → `DIAMONDS` → `ORDER_ITEMS` → `AUDIT_LOG`. Custody procedures lock the stone's `DIAMONDS` row first, then write `WORK_ORDERS` / `CUSTODY_EVENTS` / `WEIGHT_LOG`.
- **Triggers** compare old and new values with `<=>`, because grades and `certification_number` can be NULL. Triggers cannot call procedures, so a 4C change only writes a `price_update_needed` entry to the audit log. `changed_by` = `COALESCE(@app_user, 'SYSTEM_TRIGGER')`.
- **Import.** MySQL forbids `LOAD DATA` inside stored programs, so the import runs in two steps. First, `scripts/load_diamonds.sql` loads the CSV on the client into `stg_diamonds_import`, using a path relative to `diamond_company/`. Then `sp_import_diamonds` validates rows by joining them to the reference tables, skips SKUs that already exist, and derives `base_price_per_carat` so that repricing reproduces the CSV price.
- **Cut mapping.** The raw Kaggle cut names are mapped in `transform_to_gia.py`: Ideal → Excellent, Premium → Very Good.

### Diamond Tracker app (`diamond_company/app/`)

FastAPI with Jinja2 templates and HTMX, server-rendered, no build step. Run with `.venv/bin/uvicorn diamond_app.main:app`. Settings come from `app/.env` (`DT_*` variables, see `.env.example`; the real `.env` is gitignored).

- **Database access** (`db.py`). The engine runs in AUTOCOMMIT. `connect(username)` sets `@app_user` on the connection for the audit triggers.
  - **Writes** go through stored procedures via `call_procedure(conn, "sp_…", args, outs)`, so the database rules apply. The exception is the Admin page's reference data (users, employees, customers, suppliers, rough lots), which uses plain parameterized INSERT/UPDATE.
  - **Reads** are parameterized SELECTs, mostly against the views. Shared reads live in `queries.py`.
- **Security** (`security.py`):
  - argon2 password hashes;
  - signed session cookie, with the user re-read on every request so deactivation takes effect at once;
  - `require_roles(...)`; Admin always passes, and `require_roles()` with no arguments means Admin only;
  - an app-wide CSRF dependency: every POST needs the `csrf_token` form field or an `X-CSRF-Token` header;
  - a strict CSP with no inline styles or scripts, so templates must not use `style=` or inline JS. Put behavior in `static/js/app.js`.
- **Templates.**
  - Import macros with `{% from "macros.html" import … with context %}`; the macros need `request`.
  - Form errors are a dict of field name to message, shown in an error summary plus inline messages linked by `aria-describedby`.
  - Polishers never see prices (`user.sees_prices`).
- **UI design** follows `app/design-system/diamond-tracker/MASTER.md`, generated by the UI UX Pro Max skill: Flat style with no shadows, slate and emerald colors, Cormorant and Montserrat fonts. Fonts, HTMX and Lucide icons are self-hosted under `static/`, so the app works offline.
- **Certificates** are verified by magic bytes in `storage.py` and saved under random names in `app/storage/` (gitignored).

## Financial project

Each file in `financial_ledger/sql/` creates one object, and the numeric prefixes give the run order. Staging tables store every CSV field as `TEXT` plus `source_file`, `row_num` and `row_hash`. `09_load_core_from_staging.sql` trims and casts staging rows into `core`, then links each account to its parent in a second pass. In MySQL a "schema" is a database, so `core.chart_of_accounts` is a cross-database reference.
