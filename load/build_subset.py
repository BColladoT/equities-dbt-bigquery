"""Build the BigQuery load artifact (and the committed dev sample) from the parquet cache.

Two modes:

  --full    573 symbols, ~20,391,519 rows, ~291 MB  -> build/bars_1min_subset.parquet
            Every symbol that ever produced a setup. This is what `bq load` consumes.
            NOT committed (gitignored) -- far too large, and it is derived data.

  --sample   10 symbols,     220,388 rows, ~3.5 MB  -> data/sample/bars_1min_sample.parquet
            Committed to the repo so the DAG can be built and tested anywhere, including in
            environments with no access to Brian's local cache (e.g. a cloud agent, or a
            recruiter who clones the repo and wants `dbt build` to actually work).
            Real data, not synthetic. Chosen to cover all three funnel branches
            (won / lost / never_triggered) so the marts are exercised end to end.

Reads:  <ENGINE_REPO>/data/cache/1min_extended/<SYMBOL>_1min_*.parquet
        <ENGINE_REPO>/reports/full_3527_backtest_results.csv   (defines the symbol universe)

Deliberately does NOT read <ENGINE_REPO>/data/cache/*.parquet -- despite carrying `_1min_` in
their filenames, those files contain DAILY bars (verified: 86,400s modal gap, midnight-ET
timestamps). Trusting the filename there would silently mix daily and minute bars into one table.
See the README (ground-truth notes).
"""
from __future__ import annotations

import argparse
import collections
import csv
import glob
import os
import sys

import pyarrow as pa
import pyarrow.parquet as pq

ENGINE_REPO = os.environ.get("ENGINE_REPO", r"C:\quant_trading")
BARS_DIR = os.path.join(ENGINE_REPO, "data", "cache", "1min_extended")
UNIVERSE_CSV = os.path.join(ENGINE_REPO, "reports", "full_3527_backtest_results.csv")

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_FULL = os.path.join(REPO_ROOT, "build", "bars_1min_subset.parquet")
OUT_SAMPLE = os.path.join(REPO_ROOT, "data", "sample", "bars_1min_sample.parquet")

# Frozen so the sample is reproducible and reviewable rather than "whatever the script picked
# today". These are the 10 highest-setup-count symbols that also have at least one win, so the
# sample exercises won / lost / never_triggered.
SAMPLE_SYMBOLS = ["GOVX", "INDO", "MI", "PDYN", "ERNA", "XTKG", "LGVN", "GFAI", "KALA", "WAFU"]

# large_string -> string so BigQuery maps to STRING cleanly.
TARGET_SCHEMA = pa.schema([
    ("timestamp", pa.timestamp("us", tz="UTC")),
    ("open", pa.float64()),
    ("high", pa.float64()),
    ("low", pa.float64()),
    ("close", pa.float64()),
    ("volume", pa.float64()),
    ("vwap", pa.float64()),
    ("symbol", pa.string()),
])


def full_universe() -> list[str]:
    """Every symbol that produced a setup. 573 of them."""
    with open(UNIVERSE_CSV, newline="") as fh:
        return sorted({row["symbol"] for row in csv.DictReader(fh)})


def write_subset(symbols: list[str], out_path: str) -> tuple[int, list[str]]:
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    writer = None
    total_rows = 0
    missing: list[str] = []

    for sym in symbols:
        matches = glob.glob(os.path.join(BARS_DIR, f"{sym}_1min_*.parquet"))
        if not matches:
            missing.append(sym)
            continue
        table = pq.read_table(matches[0]).cast(TARGET_SCHEMA)
        if writer is None:
            writer = pq.ParquetWriter(out_path, TARGET_SCHEMA, compression="snappy")
        writer.write_table(table)
        total_rows += table.num_rows

    if writer is not None:
        writer.close()
    return total_rows, missing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--full", action="store_true", help="573 symbols -> build/ (gitignored)")
    group.add_argument("--sample", action="store_true", help="10 symbols -> data/sample/ (committed)")
    args = parser.parse_args()

    if not os.path.isdir(BARS_DIR):
        print(f"ERROR: bar cache not found at {BARS_DIR}", file=sys.stderr)
        print("       Set ENGINE_REPO to the parabolic-reversal-trading-engine checkout.", file=sys.stderr)
        print("       The committed sample at data/sample/ does not need this.", file=sys.stderr)
        return 2

    symbols = full_universe() if args.full else SAMPLE_SYMBOLS
    out_path = OUT_FULL if args.full else OUT_SAMPLE

    total_rows, missing = write_subset(symbols, out_path)

    print(f"mode             : {'full' if args.full else 'sample'}")
    print(f"symbols resolved : {len(symbols) - len(missing)}/{len(symbols)}")
    print(f"missing          : {missing or 'none'}")
    print(f"rows             : {total_rows:,}")
    print(f"output           : {out_path} ({os.path.getsize(out_path) / 1e6:.1f} MB)")
    if args.full:
        print(f"est BQ logical   : {total_rows * 62 / 1e9:.2f} GB  (free storage: 10 GiB)")
        print(f"est spend        : EUR 0.00")
        if total_rows != 20_391_519:
            print(f"WARNING: expected 20,391,519 rows, got {total_rows:,}. "
                  f"The cache or universe changed since profiling -- investigate before loading.",
                  file=sys.stderr)
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
