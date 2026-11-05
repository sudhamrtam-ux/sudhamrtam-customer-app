import sqlite3
from pathlib import Path

backup_root = Path(r"C:\Sudhamrtam\backups")

v3_file = (
    backup_root
    / "milestone_126_android_sqlite_v3"
    / "sudhamrtam_milk.db"
)

v4_file = (
    backup_root
    / "milestone_126_android_sqlite_v4"
    / "sudhamrtam_milk.db"
)

existing_tables = [
    "milk_subscriptions",
    "milk_shift_schedules",
    "cart_items",
    "customer_orders",
    "customer_order_items",
]

new_tables = [
    "customer_profiles",
    "customer_addresses",
]


def inspect_database(file_path):
    if not file_path.is_file():
        raise FileNotFoundError(file_path)

    connection = sqlite3.connect(
        file_path.as_uri() + "?mode=ro",
        uri=True,
    )

    try:
        integrity = connection.execute(
            "PRAGMA integrity_check"
        ).fetchone()[0]

        version = connection.execute(
            "PRAGMA user_version"
        ).fetchone()[0]

        tables = {
            row[0]
            for row in connection.execute(
                "SELECT name FROM sqlite_master "
                "WHERE type = 'table'"
            )
        }

        counts = {}

        for table in existing_tables:
            if table not in tables:
                raise RuntimeError(
                    f"Missing existing table: {table}"
                )

            counts[table] = connection.execute(
                f'SELECT COUNT(*) FROM "{table}"'
            ).fetchone()[0]

        return integrity, version, tables, counts

    finally:
        connection.close()


v3 = inspect_database(v3_file)
v4 = inspect_database(v4_file)

print("Version 3 backup:")
print("  Integrity:", v3[0])
print("  Database version:", v3[1])

print("\nVersion 4 backup:")
print("  Integrity:", v4[0])
print("  Database version:", v4[1])

print("\nExisting record counts:")

for table in existing_tables:
    old_count = v3[3][table]
    new_count = v4[3][table]

    status = "PASS" if old_count == new_count else "FAIL"

    print(
        f"  {table}: "
        f"v3={old_count}, v4={new_count} [{status}]"
    )

print("\nNew tables:")

for table in new_tables:
    exists = table in v4[2]

    print(
        f"  {table}: "
        f"{'PRESENT' if exists else 'MISSING'}"
    )

checks_passed = (
    v3[0] == "ok"
    and v4[0] == "ok"
    and v3[1] == 3
    and v4[1] == 4
    and all(
        v3[3][table] == v4[3][table]
        for table in existing_tables
    )
    and all(
        table in v4[2]
        for table in new_tables
    )
)

if not checks_passed:
    raise RuntimeError(
        "SQLite version 4 verification FAILED"
    )

print("\nSQLite version 4 verification: PASSED")
