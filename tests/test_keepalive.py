import os
import keepalive


def test_load_databases(monkeypatch):
    monkeypatch.setenv("DB_URL_10", "postgresql://a")
    monkeypatch.setenv("DB_URL_2", "postgresql://b")
    monkeypatch.setenv("OTHER", "x")
    assert [x[0] for x in keepalive.load_databases()] == ["DB_URL_2", "DB_URL_10"]


def test_provider_detection():
    assert keepalive.detect_provider("postgresql://x@db.supabase.co:5432/postgres") == "Supabase"
    assert keepalive.detect_provider("postgresql://x@foo.layerbase.host:5432/db") == "Layerbase"
    assert keepalive.detect_provider("postgresql://x@ep-test.neon.tech/db") == "Neon"
    assert keepalive.detect_provider("postgresql://x@my-server.example/db") == "PostgreSQL"


def test_heartbeat_simulation(monkeypatch):
    class FakeCursor:
        def __init__(self):
            self.row = ("2026-01-01", 7, "OK")
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def execute(self, *args, **kwargs): pass
        def fetchone(self): return self.row

    class FakeConnection:
        def __enter__(self): return self
        def __exit__(self, *args): pass
        def cursor(self): return FakeCursor()
        def commit(self): pass

    monkeypatch.setattr(keepalive.psycopg, "connect", lambda *a, **k: FakeConnection())
    ok, msg = keepalive.heartbeat(
        "postgresql://x@db.supabase.co:5432/postgres",
        "DB_URL_1",
    )
    assert ok is True
    assert "Supabase" in msg
    assert "update #7" in msg
