# PostgreSQL Exercises

Exercises in PostgreSQL data types and data import/export. The numeric prefixes give the order to run them in, since later scripts use tables that earlier ones create.

| Scripts | Topic |
|---|---|
| `01`–`02` | `teachers` table and sample rows |
| `03`–`05` | Character types (`char`, `varchar`, `text`) and exporting with `COPY ... TO` |
| `06`–`08` | Exact `numeric` vs floating-point `real` / `double precision` |
| `09`–`10` | `timestamp with time zone` and `interval` |
| `11` | Identity columns (`GENERATED ALWAYS AS IDENTITY`) |
| `12`–`13` | US counties 2019 population estimates: create the table and query it |

## Data

`data/us_counties_pop_est_2019.csv` loads into the table that `12_create_us_counties.sql` creates. Run this from the repository root:

```sql
\copy us_counties_pop_est_2019 FROM 'postgresql_exercises/data/us_counties_pop_est_2019.csv' WITH (FORMAT CSV, HEADER)
```

`05_export_char_data_types.sql` uses server-side `COPY`. Edit its output path before running it, or use the `\copy` alternative noted in the file.
