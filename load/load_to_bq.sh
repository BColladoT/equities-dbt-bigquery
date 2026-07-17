#!/usr/bin/env bash
# Load the 573-symbol 1-minute bar subset into BigQuery, partitioned + clustered from day one.
#
# Partitioned by UTC DATE(timestamp): the raw table is loaded faithfully as the vendor sent it
# (ELT, not ETL) -- no transformation before load. The ET session_date is derived downstream in
# staging, and the first materialised dbt model (int_bars_session_vwap) re-partitions on it. Two
# partition keys is deliberate, not a contradiction -- see the spec.
#
# Clustered by symbol: every query in this project filters or groups by symbol, so clustering
# keeps scans cheap. Partition + cluster together are what hold the bill at EUR 0.00.
#
# Prerequisites: gcloud auth done, GCP_PROJECT_ID set, dataset equities_raw created in EU,
# a budget alert already in place. This script REFUSES to run if the dataset is missing, so the
# "budget alert before load" ordering cannot be skipped by accident.
set -euo pipefail

: "${GCP_PROJECT_ID:?set GCP_PROJECT_ID to your project id (not the display name)}"

PARQUET="./build/bars_1min_subset.parquet"
TABLE="${GCP_PROJECT_ID}:equities_raw.bars_1min"

if [[ ! -f "$PARQUET" ]]; then
  echo "ERROR: $PARQUET not found. Run: python load/build_subset.py --full" >&2
  exit 1
fi

# Fail loudly if the raw dataset does not exist yet -- forces the create-dataset step (and thus
# the budget-alert-first ordering) to have happened.
if ! bq --location=EU show --dataset "${GCP_PROJECT_ID}:equities_raw" >/dev/null 2>&1; then
  echo "ERROR: dataset ${GCP_PROJECT_ID}:equities_raw does not exist." >&2
  echo "       Create it first:  bq --location=EU mk --dataset ${GCP_PROJECT_ID}:equities_raw" >&2
  exit 1
fi

echo "Loading $PARQUET -> $TABLE (partitioned by day on timestamp, clustered by symbol)..."
bq --location=EU load \
  --source_format=PARQUET \
  --time_partitioning_field=timestamp \
  --time_partitioning_type=DAY \
  --clustering_fields=symbol \
  "$TABLE" \
  "$PARQUET"

echo "Done. Verifying row count..."
bq query --location=EU --use_legacy_sql=false --format=csv \
  "SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols FROM \`${GCP_PROJECT_ID}.equities_raw.bars_1min\`"
echo "Expected: 20391519 rows, 573 symbols."
