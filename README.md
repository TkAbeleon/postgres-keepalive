# PostgreSQL Keep Alive

Lightweight Python utility that keeps multiple PostgreSQL databases active by performing a **real database write** on a dedicated heartbeat table.

It is designed to work with any PostgreSQL provider. Supabase, Layerbase, Neon and other providers can be detected when their hostname is recognizable; unknown providers simply appear as `PostgreSQL`.

## Features

- Supports any number of databases.
- Configuration only through `DB_URL_N` environment variables.
- Works with standard PostgreSQL connection URLs.
- Automatically identifies several common providers.
- Creates a dedicated `keepalive_heartbeat` table in each database.
- Performs a real `INSERT ... ON CONFLICT DO UPDATE`.
- Commits the transaction.
- Reads the result back with `RETURNING` and verifies the status.
- One database failure does not stop the others.
- Configurable interval.
- `RUN_ONCE=true` for testing.
- No application tables are modified.

## Configuration

Copy `.env.example` to `.env`:

```env
DB_URL_1=postgresql://USER:PASSWORD@HOST:5432/DATABASE?sslmode=require
DB_URL_2=postgresql://USER:PASSWORD@HOST:5432/DATABASE?sslmode=require
DB_URL_7=postgresql://USER:PASSWORD@HOST:5432/DATABASE?sslmode=require

INTERVAL_SECONDS=600
RUN_ONCE=false
```

The numbers do not have to be consecutive. `DB_URL_1`, `DB_URL_2` and `DB_URL_7` are all valid.

## Installation

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

On Windows:

```powershell
.venv\Scripts\activate
pip install -r requirements.txt
```

## Run one real cycle

Set the variables from `.env` in your shell or load them with your preferred environment manager, then:

```bash
RUN_ONCE=true python keepalive.py
```

Expected output:

```text
--- heartbeat 2026-09-18T15:30:00+03:00 ---
[OK] DB_URL_1 | Supabase: write OK, update #1
[OK] DB_URL_2 | Layerbase: write OK, update #4
[OK] DB_URL_7 | PostgreSQL: write OK, update #18
```

## Continuous mode

```bash
python keepalive.py
```

The default interval is 600 seconds (10 minutes):

```env
INTERVAL_SECONDS=600
```

## What is actually tested?

For every database:

1. Connect to PostgreSQL.
2. Create `keepalive_heartbeat` if it does not exist.
3. Insert the heartbeat row, or update the existing row.
4. Commit the transaction.
5. Verify the returned `update_count` and `last_status`.

This means a successful heartbeat demonstrates more than a TCP connection: the configured database account could create the dedicated table, write to it, and commit the transaction.

## Security

**Never commit `.env`.** It contains database credentials.

Use:

```bash
git status
```

before pushing and verify that `.env` is not tracked.

The heartbeat table contains only operational metadata:

- provider name
- last update timestamp
- update counter
- status

## Simulation / tests

The repository includes tests that simulate a PostgreSQL connection, so the provider detection, database discovery and heartbeat logic can be checked without touching a real database.

```bash
pip install pytest
pytest -q
```

The simulation verifies that:

- multiple `DB_URL_N` variables are discovered;
- numbering may be non-consecutive;
- common providers are detected;
- a simulated `INSERT/UPDATE + COMMIT + verification` is reported as successful.

For a real end-to-end test, use `RUN_ONCE=true` with a test PostgreSQL database.

## Limitations

This utility does not guarantee that a provider will never pause a project. Provider-specific suspension policies can change, and activity requirements are controlled by each provider.

The program is intentionally PostgreSQL-specific. It does not attempt to support MySQL, MongoDB, SQLite, etc.

## License

MIT
