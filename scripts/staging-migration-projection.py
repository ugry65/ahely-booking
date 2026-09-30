#!/usr/bin/env python3
"""Guarded, temporary CLI projection of the *actual* staging migration lineage.

The repository keeps original historical SQL for clean rebuilds. The staging
lineage contains renamed and one-time UAT migrations. Never replay those files
or insert artificial history rows merely to satisfy a filename comparison.
"""

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys


def fail(message: str) -> None:
    raise SystemExit(f"Unsafe staging migration history: {message}")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--history", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    baseline = json.loads((root / "scripts/staging-migration-history-baseline.json").read_text())
    actual = json.loads(args.history.read_text())
    if actual != baseline["applied"]:
        fail("remote version/name/SQL checksum differs from the pinned read-only baseline")
    if len({row["version"] for row in actual}) != len(actual):
        fail("duplicate remote migration version")
    protected = {
        "20260927103201",
        "20260927103212",
    }
    if not protected.issubset({row["version"] for row in actual}):
        fail("one-time UAT migration history is missing; replay is forbidden")

    excluded = {item["file"]: item["sha256"] for item in baseline["excluded_local"]}
    approved_older = baseline["approved_out_of_order"]
    applied_versions = {row["version"] for row in actual}
    last_applied = max(applied_versions)
    migrations = args.output / "supabase/migrations"
    migrations.mkdir(parents=True, exist_ok=False)
    shutil.copy2(root / "supabase/config.toml", args.output / "supabase/config.toml")

    for row in actual:
        name = re.sub(r"[^A-Za-z0-9_]", "_", row["name"])
        path = migrations / f'{row["version"]}_{name}.sql'
        # If a supposedly applied row disappears after our snapshot, this
        # guard aborts before any historical SQL or data can run.
        path.write_text(
            "do $migration_replay_guard$ begin raise exception "
            f"'Historical migration {row['version']} must never be replayed'; "
            "end $migration_replay_guard$;\n"
        )

    pending = []
    seen_excluded = set()
    for source in sorted((root / "supabase/migrations").glob("*.sql")):
        match = re.fullmatch(r"(\d+)_([A-Za-z0-9_]+)\.sql", source.name)
        if match is None:
            fail(f"unexpected local migration filename {source.name}")
        version = match.group(1)
        if source.name in excluded:
            if sha256(source) != excluded[source.name]:
                fail(f"historical local migration changed: {source.name}")
            seen_excluded.add(source.name)
            continue
        if version in applied_versions:
            # The remote row is independently pinned by version/name/SQL MD5.
            continue
        if version <= last_applied and approved_older.get(source.name) != sha256(source):
            fail(f"unrecognized old local migration: {source.name}")
        if (migrations / source.name).exists():
            fail(f"duplicate projected migration version: {source.name}")
        shutil.copy2(source, migrations / source.name)
        pending.append(source.name)
    if seen_excluded != set(excluded):
        fail(f"missing historical local files: {sorted(set(excluded) - seen_excluded)}")
    print(json.dumps({"remote_applied": len(actual), "pending": pending}, ensure_ascii=False))


if __name__ == "__main__":
    main()
