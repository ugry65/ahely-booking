#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import os
import re
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from zoneinfo import ZoneInfo

BUDAPEST = ZoneInfo("Europe/Budapest")
UTC = dt.timezone.utc
ARTIFACT_RE = re.compile(
    r"^ahely-booking-production_(?P<timestamp>\d{8}T\d{6}Z)_(?P<git>[0-9a-f]{12})\.tar\.gz\.age$"
)


@dataclass(frozen=True)
class Backup:
    name: str
    timestamp_utc: dt.datetime

    @property
    def local_date(self) -> dt.date:
        return self.timestamp_utc.astimezone(BUDAPEST).date()

    @property
    def local_month(self) -> tuple[int, int]:
        local = self.timestamp_utc.astimezone(BUDAPEST)
        return (local.year, local.month)


def run(*args: str, capture: bool = False) -> str:
    completed = subprocess.run(
        args,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=None,
    )
    return completed.stdout if capture else ""


def parse_now() -> dt.datetime:
    override = os.environ.get("RETENTION_NOW_UTC")
    if override:
        value = dt.datetime.fromisoformat(override.replace("Z", "+00:00"))
        if value.tzinfo is None:
            raise ValueError("RETENTION_NOW_UTC must include timezone")
        return value.astimezone(UTC)
    return dt.datetime.now(tz=UTC)


def subtract_months(date: dt.date, months: int) -> dt.date:
    month_index = date.year * 12 + (date.month - 1) - months
    year, month_zero = divmod(month_index, 12)
    month = month_zero + 1
    # Retention boundaries only need a stable calendar-month cutoff.
    return dt.date(year, month, 1)


def list_remote(remote: str) -> set[str]:
    output = run("rclone", "lsf", remote, "--files-only", capture=True)
    return {line.strip() for line in output.splitlines() if line.strip()}


def parse_backups(files: set[str]) -> tuple[list[Backup], list[str]]:
    backups: list[Backup] = []
    errors: list[str] = []
    for name in sorted(files):
        if not name.endswith(".tar.gz.age"):
            continue
        match = ARTIFACT_RE.fullmatch(name)
        if not match:
            # Unknown files are deliberately ignored rather than deleted.
            print(f"WARN unrecognized artifact filename, keeping: {name}", file=sys.stderr)
            continue
        timestamp = dt.datetime.strptime(match.group("timestamp"), "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC)
        sidecar = f"{name}.sha256"
        if sidecar not in files:
            errors.append(f"recognized artifact is missing checksum sidecar: {name}")
            continue
        backups.append(Backup(name=name, timestamp_utc=timestamp))
    return backups, errors


def retention_candidates(backups: list[Backup], now: dt.datetime, b2: bool) -> tuple[set[str], set[str]]:
    keep: set[str] = set()
    delete: set[str] = set()

    cutoff_15 = now - dt.timedelta(days=15)
    cutoff_30 = now - dt.timedelta(days=30)
    cutoff_90 = now - dt.timedelta(days=90)
    cutoff_24_months = subtract_months(now.astimezone(BUDAPEST).date(), 24)

    daily_groups: dict[dt.date, list[Backup]] = defaultdict(list)
    monthly_groups: dict[tuple[int, int], list[Backup]] = defaultdict(list)

    for backup in backups:
        if backup.timestamp_utc >= cutoff_15:
            keep.add(backup.name)
            continue
        if b2 and backup.timestamp_utc >= cutoff_30:
            # 30-day Governance Object Lock intentionally keeps all B2 restore points.
            keep.add(backup.name)
            continue
        if backup.timestamp_utc >= cutoff_90:
            daily_groups[backup.local_date].append(backup)
            continue
        if backup.local_date >= cutoff_24_months:
            monthly_groups[backup.local_month].append(backup)
            continue
        delete.add(backup.name)

    for group in daily_groups.values():
        newest = max(group, key=lambda item: item.timestamp_utc)
        keep.add(newest.name)
        delete.update(item.name for item in group if item.name != newest.name)

    for group in monthly_groups.values():
        newest = max(group, key=lambda item: item.timestamp_utc)
        keep.add(newest.name)
        delete.update(item.name for item in group if item.name != newest.name)

    return keep, delete


def process_remote(label: str, remote: str, now: dt.datetime, apply: bool, b2: bool) -> int:
    files = list_remote(remote)
    backups, errors = parse_backups(files)
    if errors:
        for error in errors:
            print(f"ERROR {label}: {error}", file=sys.stderr)
        return 2

    keep, delete = retention_candidates(backups, now, b2=b2)
    print(f"{label}: recognized={len(backups)} keep={len(keep)} delete={len(delete)} mode={'APPLY' if apply else 'DRY-RUN'}")

    for name in sorted(delete):
        sidecar = f"{name}.sha256"
        if sidecar not in files:
            print(f"ERROR {label}: checksum sidecar disappeared before deletion: {name}", file=sys.stderr)
            return 2
        if apply:
            run("rclone", "deletefile", f"{remote.rstrip('/')}/{name}")
            run("rclone", "deletefile", f"{remote.rstrip('/')}/{sidecar}")
            print(f"DELETE {label}: {name} + sidecar")
        else:
            print(f"WOULD_DELETE {label}: {name} + sidecar")

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply A-Hely production backup retention policy safely.")
    parser.add_argument("--apply", action="store_true", help="Actually delete eligible backup pairs. Default is dry-run.")
    args = parser.parse_args()

    gdrive = os.environ.get("BACKUP_GDRIVE_REMOTE")
    b2 = os.environ.get("BACKUP_B2_REMOTE")
    if not gdrive or not b2:
        print("Missing BACKUP_GDRIVE_REMOTE or BACKUP_B2_REMOTE", file=sys.stderr)
        return 2

    try:
        now = parse_now()
        gdrive_status = process_remote("Google Drive", gdrive, now, args.apply, b2=False)
        b2_status = process_remote("Backblaze B2", b2, now, args.apply, b2=True)
    except (subprocess.CalledProcessError, ValueError) as exc:
        print(f"Retention failed: {exc}", file=sys.stderr)
        return 2

    return 0 if gdrive_status == 0 and b2_status == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
