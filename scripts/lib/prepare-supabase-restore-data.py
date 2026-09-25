#!/usr/bin/env python3
"""Make a Supabase CLI data-only dump safe for an isolated restore target.

Supabase-managed schemas can be newer on the hosted platform than in the local
CLI stack. We may omit only EMPTY COPY blocks for incompatible managed tables.
Any non-empty incompatible block fails closed so auth/storage data is never
silently lost.
"""
from __future__ import annotations
import argparse, re, sys
from pathlib import Path

COPY_RE = re.compile(r'^COPY (?P<table>(?:"[^"]+"|[^.\s]+)\.(?:"[^"]+"|[^\s(]+)) \((?P<cols>.*)\) FROM stdin;$')

def unquote(s: str) -> str:
    return s[1:-1].replace('""','"') if s.startswith('"') and s.endswith('"') else s

def parse_target(path: Path):
    out={}
    for raw in path.read_text().splitlines():
        if not raw.strip(): continue
        table, cols = raw.split("\t",1)
        out[table] = set(cols.split(",")) if cols else set()
    return out

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--output", required=True)
    ap.add_argument("--target-columns", required=True)
    args=ap.parse_args()
    target=parse_target(Path(args.target_columns))
    lines=Path(args.input).read_text().splitlines(keepends=True)
    out=[]; skipped=[]; i=0
    while i < len(lines):
        line=lines[i]
        m=COPY_RE.match(line.rstrip("\n"))
        if not m:
            out.append(line); i+=1; continue
        table_raw=m.group("table")
        parts=table_raw.split(".",1)
        table=f"{unquote(parts[0])}.{unquote(parts[1])}"
        cols=[unquote(x.strip()) for x in m.group("cols").split(",")]
        j=i+1
        while j < len(lines) and lines[j].rstrip("\n") != r"\.":
            j+=1
        if j >= len(lines):
            raise SystemExit(f"Unterminated COPY block: {table}")
        row_count=j-i-1
        target_cols=target.get(table)
        missing_table=target_cols is None
        missing_cols=[] if missing_table else [c for c in cols if c not in target_cols]
        incompatible=missing_table or bool(missing_cols)
        managed=table.startswith("auth.") or table.startswith("storage.")
        if incompatible:
            detail="missing target table" if missing_table else "missing target columns: "+",".join(missing_cols)
            if managed and row_count == 0:
                skipped.append(f"{table} ({detail})")
                i=j+1
                continue
            print(f"Incompatible non-skippable COPY block: {table}; rows={row_count}; {detail}", file=sys.stderr)
            return 2
        out.extend(lines[i:j+1]); i=j+1
    Path(args.output).write_text("".join(out))
    for item in skipped:
        print(f"Skipped empty managed-schema COPY block: {item}")
    print(f"Managed-schema compatibility preflight PASS; skipped_empty_blocks={len(skipped)}")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
