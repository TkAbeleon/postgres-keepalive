#!/usr/bin/env python3
"""Lightweight multi-PostgreSQL keep-alive with a real INSERT/UPDATE heartbeat."""

from __future__ import annotations

import os
import re
import sys
import time
from datetime import datetime, timezone
from urllib.parse import urlparse

import psycopg
from dotenv import load_dotenv
from psycopg import sql

DB_PATTERN = re.compile(r"^DB_URL_(\d+)$")
TABLE_NAME = "keepalive_heartbeat"

# Load .env when present. Existing environment variables keep precedence.
load_dotenv(override=False)


def load_databases() -> list[tuple[str, str]]:
    items = []
    for key, value in os.environ.items():
        match = DB_PATTERN.match(key)
        if match and value.strip():
            items.append((int(match.group(1)), value.strip()))
    items.sort()
    return [(f"DB_URL_{number}", url) for number, url in items]


def detect_provider(url: str) -> str:
    host = (urlparse(url).hostname or "").lower()
    if "supabase" in host:
        return "Supabase"
    if "layerbase" in host:
        return "Layerbase"
    if "neon" in host:
        return "Neon"
    if "railway" in host:
        return "Railway"
    if "render" in host:
        return "Render"
    return "PostgreSQL"


def ensure_table(conn) -> None:
    with conn.cursor() as cur:
        cur.execute(
            sql.SQL("""
                CREATE TABLE IF NOT EXISTS {} (
                    id INTEGER PRIMARY KEY,
                    provider VARCHAR(100) NOT NULL,
                    last_update TIMESTAMPTZ NOT NULL,
                    update_count BIGINT NOT NULL DEFAULT 0,
                    last_status VARCHAR(20) NOT NULL
                )
            """).format(sql.Identifier(TABLE_NAME))
        )
    conn.commit()


def heartbeat(url: str, key: str) -> tuple[bool, str]:
    provider = detect_provider(url)
    try:
        with psycopg.connect(url, connect_timeout=10) as conn:
            ensure_table(conn)

            now = datetime.now(timezone.utc)
            with conn.cursor() as cur:
                cur.execute(
                    sql.SQL("""
                        INSERT INTO {} (id, provider, last_update, update_count, last_status)
                        VALUES (1, %s, %s, 1, 'OK')
                        ON CONFLICT (id) DO UPDATE SET
                            provider = EXCLUDED.provider,
                            last_update = EXCLUDED.last_update,
                            update_count = {}.update_count + 1,
                            last_status = 'OK'
                        RETURNING last_update, update_count, last_status
                    """).format(
                        sql.Identifier(TABLE_NAME),
                        sql.Identifier(TABLE_NAME),
                    ),
                    (provider, now),
                )
                row = cur.fetchone()

            conn.commit()

            if not row or row[2] != "OK" or row[1] < 1:
                return False, f"{provider}: verification failed"

            return True, f"{provider}: write OK, update #{row[1]}"
    except Exception as exc:
        return False, f"{provider}: {type(exc).__name__}: {exc}"


def run_once() -> int:
    databases = load_databases()
    if not databases:
        print("No DB_URL_N variables found.", file=sys.stderr)
        return 1

    failed = 0
    for key, url in databases:
        ok, message = heartbeat(url, key)
        print(f"[{'OK' if ok else 'ERROR'}] {key} | {message}")
        if not ok:
            failed += 1
    return 1 if failed else 0


def get_interval() -> int:
    raw = os.getenv("INTERVAL_SECONDS", "600").strip()
    try:
        interval = int(raw)
    except ValueError as exc:
        raise ValueError("INTERVAL_SECONDS must be an integer >= 1") from exc
    if interval < 1:
        raise ValueError("INTERVAL_SECONDS must be >= 1")
    return interval


def main() -> int:
    try:
        interval = get_interval()
    except ValueError as exc:
        print(f"Configuration error: {exc}", file=sys.stderr)
        return 2

    once = os.getenv("RUN_ONCE", "false").strip().lower() in {"1", "true", "yes"}

    while True:
        print(
            f"\n--- heartbeat "
            f"{datetime.now().astimezone().isoformat(timespec='seconds')} ---",
            flush=True,
        )
        result = run_once()
        if once:
            return result
        time.sleep(interval)


if __name__ == "__main__":
    sys.exit(main())
