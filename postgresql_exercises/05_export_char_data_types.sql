-- Server-side COPY writes to a path on the database server.
-- Replace the path below, or use psql's client-side \copy instead:
--   \copy char_table_types TO 'typetest.txt' WITH (FORMAT CSV, HEADER, DELIMITER '|')
COPY char_table_types TO '/path/to/typetest.txt'
WITH (FORMAT CSV, HEADER, DELIMITER '|');
