# SQL Projects Repository

## Overview
This repository hosts **SQL scripts and exercises** for learning and practicing database design, querying, and optimization. Projects are inspired by textbooks and real-world data scenarios.

## Projects

| Folder | Engine | Description |
|---|---|---|
| [diamond_company/](diamond_company/) | MySQL 8.0+ | Diamond business database graded on the GIA 4Cs: procedures, triggers, views, CSV import |
| [financial_ledger/](financial_ledger/) | MySQL 8.0+ | General ledger with `staging` → `core` → `mart` layers |
| [mysql_exercises/](mysql_exercises/) | MySQL | Query exercises on the `my_guitar_shop` sample database |
| [postgresql_exercises/](postgresql_exercises/) | PostgreSQL | Data types, `COPY` import/export, and the US counties dataset |

## Conventions
- **File names.** All names are `snake_case` with no spaces. Scripts that must run in a set order have numeric prefixes (`01_`, `02_`, …).
- **Data files.** Source data lives in each project's `data/` folder. Generated files are gitignored.
- **Credentials.** No credentials are stored here. Connect with `mysql -p` (password prompt) or `mysql_config_editor`, and with `~/.pgpass` for PostgreSQL. Local credential files are gitignored.

## How to Use
1. Clone the repository:
   ```bash
   git clone https://github.com/Emmanuel-Esplin/SQL-Projects.git
   ```
2. Follow the README in each project folder.

## GitHub Profile
https://github.com/Emmanuel-Esplin/SQL-Projects
