
import hashlib
import sqlite3
from pathlib import Path

backup = Path(
    r"C:\Sudhamrtam\backups"
    r"\milestone_126_android_sqlite_v3"
    r"\sudhamrtam_milk.db"
)

if not backup.is_file():
    raise FileNotFoundError(f"Backup not found: {backup}")

data = backup.read_bytes()

print("Backup size:", len(data), "bytes")
print("SHA256:", hashlib.sha256(data).hexdigest())

connection = sqlite3.connect(
    backup.as_uri() + "?mode=ro",
    uri=True,
)

try:
    integrity = connection.execute(
        "PRAGMA integrity_check"
    ).fetchone()[0]

    version = connection.execute(
        "PRAGMA user_version"
    ).fetchone()[0]

    tables = connection.execute("""
        SELECT name
        FROM sqlite_master
        WHERE type = 'table'
          AND name NOT LIKE 'sqlite_%'
        ORDER BY name
    """).fetchall()

    print("Integrity:", integrity)
    print("Database version:", version)

    print("Tables:")
    for (table_name,) in tables:
        print(" -", table_name)

    if integrity != "ok":
        raise RuntimeError("SQLite integrity check failed")

    if version != 3:
        raise RuntimeError(
            f"Expected version 3, found {version}"
        )

    print("Backup verification: PASSED")

finally:
    connection.close()
