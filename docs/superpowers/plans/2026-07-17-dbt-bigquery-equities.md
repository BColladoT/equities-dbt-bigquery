# dbt + BigQuery + Looker Studio Implementation Plan

> **For agentic workers: DO NOT dispatch subagents against this plan.**
> The writing-plans skill defaults to subagent-driven execution. That default is **overridden
> here** by the project brief: the entire point is that Brian can defend every model under
> hostile questioning. A fleet of subagents would produce a clean repo he did not build — the
> exact failure this project exists to prevent. Execute **inline, in session**, honouring the
> explain-back gates. Steps use `- [ ]` for tracking.

**Goal:** A defensible dbt Core project over 20.4M 1-minute equity bars in BigQuery, surfacing a
signal-candidate mart and a setup funnel, with a Looker Studio dashboard and an INTERVIEW.md
written in Brian's own words.

**Architecture:** `bq load` puts raw Alpaca bars into `equities_raw.bars_1min` (partitioned by UTC
date, clustered by symbol). dbt builds 3 staging views → 4 intermediate models → 2 marts, across
separate BigQuery datasets per layer so "marts are what BI touches" is physically true. Two CSV
seeds carry the backtest results. Looker Studio reads `equities_marts` only.

**Tech Stack:** Python 3.10, dbt-core 1.12.0, dbt-bigquery 1.12.0, dbt_utils, BigQuery (EU),
Looker Studio, pyarrow (loader only).

## Global Constraints

Every task's requirements implicitly include this section.

- **Thresholds are FROZEN** at `v5_strict.py:47-50` values: `close/vwap >= 1.15`,
  `volume/vol_peak <= 0.70`, `close/day_high >= 0.93`, `day_gain >= 0.50`, window `09:45–14:00 ET`
  inclusive. **Never tune these to make counts match the backtest.** A divergence is a finding.
- **Python 3.10 only**: `C:\Users\brian\AppData\Local\Programs\Python\Python310\python.exe`.
  **Never** `pip install` into `C:\Users\brian\AppData\Local\hermes\hermes-agent\venv` (a foreign
  tool's venv, and what bare `python` resolves to) or `C:\quant_trading\venv` (broken native DLLs).
- **Budget alert exists BEFORE any data is loaded.** Non-negotiable ordering.
- **Never `SELECT *` on `equities_raw.bars_1min`** outside the staging view.
- **Data source is `data/cache/1min_extended/` ONLY.** `data/cache/*.parquet` (root) are DAILY
  bars despite `_1min_` filenames.
- **Every surfaced number carries the qualifier:** in-sample; walk-forward out-of-sample pending.
- **Brian explains each layer back in his own words before the next layer starts.** If he can't,
  stop and go again. Do not proceed on a nod.
- **INTERVIEW.md is written by Brian, not by Claude.** Any part he did not walk through himself is
  recorded there as such.
- Card entry / billing signup is performed by Brian. Never delegated.

## File Structure

```
C:\equities-dbt-bigquery\
├── .gitignore                       exists
├── README.md                        Task 13
├── INTERVIEW.md                     Task 14  (Brian's words)
├── requirements.txt                 Task 1
├── dbt_project.yml                  Task 5
├── packages.yml                     Task 5   (dbt_utils)
├── build/bars_1min_subset.parquet   Task 3   (gitignored, 291MB)
├── load/
│   ├── build_subset.py              Task 3   573 parquet → 1 parquet
│   └── load_to_bq.sh                Task 4   bq load, partitioned + clustered
├── seeds/
│   ├── setups.csv                   Task 5   ← reports/full_3527_setups.csv
│   ├── backtest_results.csv         Task 5   ← reports/full_3527_backtest_results.csv
│   └── _seeds.yml                   Task 5
├── models/
│   ├── staging/
│   │   ├── _alpaca__sources.yml     Task 5
│   │   ├── _staging__models.yml     Task 6   (tests live here)
│   │   ├── stg_alpaca__bars_1min.sql        Task 6
│   │   ├── stg_backtest__setups.sql         Task 6
│   │   └── stg_backtest__results.sql        Task 6
│   ├── intermediate/
│   │   ├── _intermediate__models.yml        Task 8
│   │   ├── int_bars_session_vwap.sql        Task 7
│   │   ├── int_bars_exhaustion.sql          Task 8
│   │   ├── int_session_features.sql         Task 8
│   │   └── int_setup_outcomes.sql           Task 8
│   └── marts/
│       ├── _marts__models.yml       Task 9
│       ├── fct_signal_candidates.sql        Task 9
│       └── fct_setup_funnel.sql             Task 10
└── tests/
    ├── assert_no_malformed_bars.sql         Task 6
    └── assert_signals_within_market_hours.sql Task 9
```

BigQuery datasets (all `EU`): `equities_raw` (bq load) → `equities_staging`, `equities_intermediate`,
`equities_marts` (dbt-created). Looker Studio is granted `equities_marts` **only**.

---

### Task 1: Python 3.10 venv + dbt Core

**Files:**
- Create: `C:\equities-dbt-bigquery\requirements.txt`
- Create: `C:\equities-dbt-bigquery\.venv\` (gitignored)

**Interfaces:**
- Produces: `.venv\Scripts\dbt.exe` on PATH when activated; `.venv\Scripts\python.exe` (3.10.0)

- [ ] **Step 1: Create the venv from Python 3.10 explicitly**

```powershell
& "C:\Users\brian\AppData\Local\Programs\Python\Python310\python.exe" -m venv C:\equities-dbt-bigquery\.venv
```

Never `py -m venv` (launcher is broken) and never bare `python` (resolves to the hermes venv).

- [ ] **Step 2: Verify the venv is 3.10 and is NOT the hermes venv**

```powershell
& C:\equities-dbt-bigquery\.venv\Scripts\python.exe -c "import sys; print(sys.version); print(sys.prefix)"
```

Expected: `3.10.0`, prefix `C:\equities-dbt-bigquery\.venv`. If prefix mentions `hermes`, STOP.

- [ ] **Step 3: Write requirements.txt**

```
dbt-core==1.12.0
dbt-bigquery==1.12.0
pyarrow==25.0.0
```

- [ ] **Step 4: Install**

```powershell
& C:\equities-dbt-bigquery\.venv\Scripts\python.exe -m pip install --upgrade pip
& C:\equities-dbt-bigquery\.venv\Scripts\python.exe -m pip install -r C:\equities-dbt-bigquery\requirements.txt
```

- [ ] **Step 5: Verify dbt runs**

```powershell
& C:\equities-dbt-bigquery\.venv\Scripts\dbt.exe --version
```

Expected: `installed: 1.12.0`, `bigquery: 1.12.0`. If ImportError, capture it — do not paper over.

- [ ] **Step 6: Commit**

```bash
cd /c/equities-dbt-bigquery && git add requirements.txt && git commit -m "build: pin dbt-core 1.12.0 + dbt-bigquery 1.12.0 on Python 3.10"
```

---

### Task 2: GCP project, billing, BUDGET ALERT, datasets

**Brian performs all browser/billing steps. Claude does not enter card details.**

**Interfaces:**
- Produces: env var `GCP_PROJECT_ID`; datasets `equities_raw` etc. in `EU`; ADC credentials

- [ ] **Step 1: Install gcloud CLI**

Download the Windows installer from https://cloud.google.com/sdk/docs/install and run it.
Verify: `gcloud --version` (expect `Google Cloud SDK`, and a `bq` version line).

- [ ] **Step 2: Brian creates the GCP project (browser)**

https://console.cloud.google.com/projectcreate — name it `equities-dbt`. Record the **project ID**
(auto-suffixed, e.g. `equities-dbt-412345`). Project ID ≠ project name.

- [ ] **Step 3: Brian attaches billing (browser)**

https://console.cloud.google.com/billing — create a billing account, attach it to the project.
Card required even for free tier. **Claude does not perform this step.**

- [ ] **Step 4: BUDGET ALERT — before any data exists**

https://console.cloud.google.com/billing → Budgets & alerts → Create budget.
Amount: **€1**. Alert thresholds: **50%, 90%, 100%** of actual spend, email to
brian.collado7@gmail.com. Scope to the `equities-dbt` project.

Verify it exists before Step 5. **If this step is skipped, stop the whole plan.**

- [ ] **Step 5: Authenticate + set project**

```powershell
gcloud auth login
gcloud auth application-default login
gcloud config set project <PROJECT_ID>
$env:GCP_PROJECT_ID = "<PROJECT_ID>"
```

`application-default login` is what dbt's `method: oauth` uses. No service-account key file is
created — nothing secret to leak into git.

- [ ] **Step 6: Enable the BigQuery API**

```powershell
gcloud services enable bigquery.googleapis.com
```

- [ ] **Step 7: Create the raw dataset in EU**

```powershell
bq --location=EU mk --dataset "$env:GCP_PROJECT_ID`:equities_raw"
```

EU chosen deliberately: Brian is Madrid-based targeting Spanish financial firms, and data
residency is a question they ask. dbt creates the other three datasets itself.

- [ ] **Step 8: Verify**

```powershell
bq ls --location=EU
```

Expected: `equities_raw` listed. Commit nothing (no files changed).

---

### Task 3: Build the subset parquet + state the cost

**Files:**
- Create: `C:\equities-dbt-bigquery\load\build_subset.py`
- Modify: `.gitignore` (add `build/`)

**Interfaces:**
- Produces: `build/bars_1min_subset.parquet` — 20,391,519 rows, ~291MB, schema below

- [ ] **Step 1: Write the loader**

```python
"""Concatenate the 573 setup-symbol parquet files into one file for `bq load`.

Reads:  <ENGINE_REPO>/data/cache/1min_extended/<SYMBOL>_1min_*.parquet
        <ENGINE_REPO>/reports/full_3527_backtest_results.csv   (defines the symbol universe)
Writes: build/bars_1min_subset.parquet

Deliberately does NOT read <ENGINE_REPO>/data/cache/*.parquet -- those are DAILY bars despite
carrying `_1min_` in the filename. See spec section 2.
"""
from __future__ import annotations

import csv
import glob
import os

import pyarrow as pa
import pyarrow.parquet as pq

ENGINE_REPO = os.environ.get("ENGINE_REPO", r"C:\quant_trading")
BARS_DIR = os.path.join(ENGINE_REPO, "data", "cache", "1min_extended")
UNIVERSE_CSV = os.path.join(ENGINE_REPO, "reports", "full_3527_backtest_results.csv")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "bars_1min_subset.parquet")

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


def symbol_universe() -> list[str]:
    with open(UNIVERSE_CSV, newline="") as fh:
        return sorted({row["symbol"] for row in csv.DictReader(fh)})


def main() -> int:
    symbols = symbol_universe()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)

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
            writer = pq.ParquetWriter(OUT, TARGET_SCHEMA, compression="snappy")
        writer.write_table(table)
        total_rows += table.num_rows

    if writer is not None:
        writer.close()

    print(f"symbols resolved : {len(symbols) - len(missing)}/{len(symbols)}")
    print(f"missing          : {missing or 'none'}")
    print(f"rows             : {total_rows:,}")
    print(f"output           : {OUT} ({os.path.getsize(OUT) / 1e6:.0f} MB)")
    print(f"est BQ logical   : {total_rows * 62 / 1e9:.2f} GB  (free storage: 10 GiB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 2: Run it**

```powershell
& C:\equities-dbt-bigquery\.venv\Scripts\python.exe C:\equities-dbt-bigquery\load\build_subset.py
```

Expected, exactly:
```
symbols resolved : 573/573
missing          : none
rows             : 20,391,519
est BQ logical   : 1.26 GB  (free storage: 10 GiB)
```

If rows ≠ 20,391,519, STOP — the universe or the cache changed since profiling.

- [ ] **Step 3: State the cost out loud before loading**

Storage 1.26 GB against a 10 GiB free tier; one full scan 0.0013 TiB against 1 TiB/month.
**Estimated spend: €0.00.** Per the brief: if this is not ~zero, stop and say so.

- [ ] **Step 4: Commit** (`build/` is gitignored — the 291MB artifact is never committed)

```bash
cd /c/equities-dbt-bigquery && printf 'build/\n' >> .gitignore && git add .gitignore load/build_subset.py && git commit -m "feat(load): build 573-symbol subset parquet for bq load"
```

---

### Task 4: Load to BigQuery, partitioned + clustered

**Files:**
- Create: `C:\equities-dbt-bigquery\load\load_to_bq.sh`

**Interfaces:**
- Consumes: `build/bars_1min_subset.parquet`
- Produces: table `<PROJECT>.equities_raw.bars_1min`, partitioned by `DATE(timestamp)` UTC,
  clustered by `symbol`, 20,391,519 rows

- [ ] **Step 1: Confirm the budget alert from Task 2 Step 4 exists.** If not, stop.

- [ ] **Step 2: Write the load script**

```bash
#!/usr/bin/env bash
# Load the 573-symbol 1-min bar subset into BigQuery, partitioned + clustered from day one.
#
# Partitioned by UTC DATE(timestamp) -- the raw table is loaded faithfully as the vendor sent it
# (ELT, not ETL). The ET session_date is derived downstream in staging, and the first materialised
# model (int_bars_session_vwap) re-partitions on it. See spec 6.
set -euo pipefail

: "${GCP_PROJECT_ID:?set GCP_PROJECT_ID}"

bq --location=EU load \
  --source_format=PARQUET \
  --time_partitioning_field=timestamp \
  --time_partitioning_type=DAY \
  --clustering_fields=symbol \
  "${GCP_PROJECT_ID}:equities_raw.bars_1min" \
  ./build/bars_1min_subset.parquet
```

- [ ] **Step 3: Run it**

```bash
cd /c/equities-dbt-bigquery && bash load/load_to_bq.sh
```

Expected: `Current status: DONE`. If the local upload is rejected for size, fall back to GCS:

```bash
gsutil mb -l EU "gs://${GCP_PROJECT_ID}-equities-load"
gsutil cp ./build/bars_1min_subset.parquet "gs://${GCP_PROJECT_ID}-equities-load/"
bq --location=EU load --source_format=PARQUET \
  --time_partitioning_field=timestamp --time_partitioning_type=DAY \
  --clustering_fields=symbol \
  "${GCP_PROJECT_ID}:equities_raw.bars_1min" \
  "gs://${GCP_PROJECT_ID}-equities-load/bars_1min_subset.parquet"
gsutil rm -r "gs://${GCP_PROJECT_ID}-equities-load"   # delete immediately; keeps storage at zero
```

- [ ] **Step 4: Verify row count matches the profile exactly**

```bash
bq query --location=EU --use_legacy_sql=false --format=csv \
  'SELECT COUNT(*) AS rows, COUNT(DISTINCT symbol) AS symbols FROM `'"${GCP_PROJECT_ID}"'.equities_raw.bars_1min`'
```

Expected: `20391519,573`. Anything else means a partial or doubled load — fix before proceeding.

- [ ] **Step 5: Prove partition pruning works (this is the money shot for the README)**

```bash
bq query --location=EU --use_legacy_sql=false --dry_run \
  'SELECT COUNT(*) FROM `'"${GCP_PROJECT_ID}"'.equities_raw.bars_1min` WHERE DATE(timestamp) = "2021-06-02"'
bq query --location=EU --use_legacy_sql=false --dry_run \
  'SELECT COUNT(*) FROM `'"${GCP_PROJECT_ID}"'.equities_raw.bars_1min`'
```

`--dry_run` reports bytes billed without running or charging. The filtered query should report
*orders of magnitude* fewer bytes. **Record both numbers** — they are the concrete answer to
"how does partitioning save you money here?" in INTERVIEW.md. A guessed answer is worthless; a
measured one is not.

- [ ] **Step 6: Commit**

```bash
cd /c/equities-dbt-bigquery && git add load/load_to_bq.sh && git commit -m "feat(load): bq load partitioned by date, clustered by symbol"
```

---

### Task 5: dbt scaffold, sources, seeds

**Files:**
- Create: `dbt_project.yml`, `packages.yml`, `~/.dbt/profiles.yml`,
  `models/staging/_alpaca__sources.yml`, `seeds/_seeds.yml`, `seeds/setups.csv`,
  `seeds/backtest_results.csv`

**Interfaces:**
- Produces: `source('alpaca','bars_1min')`, `ref('setups')`, `ref('backtest_results')`

- [ ] **Step 1: `dbt_project.yml`**

```yaml
name: 'equities'
version: '1.0.0'
config-version: 2
profile: 'equities'

model-paths: ["models"]
seed-paths: ["seeds"]
test-paths: ["tests"]
target-path: "target"
clean-targets: ["target", "dbt_packages"]

models:
  equities:
    staging:
      +materialized: view
      +schema: staging
    intermediate:
      +materialized: table
      +schema: intermediate
    marts:
      +materialized: table
      +schema: marts

seeds:
  equities:
    +schema: raw
```

Per-layer `+schema` puts each layer in its own BigQuery dataset. That makes "marts are what BI
touches" **physically enforceable** — Looker Studio gets access to `equities_marts` and nothing else.

- [ ] **Step 2: `packages.yml`**

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.1.0", "<2.0.0"]
```

- [ ] **Step 3: `~/.dbt/profiles.yml`** (outside the repo — never committed)

```yaml
equities:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: "{{ env_var('GCP_PROJECT_ID') }}"
      dataset: equities
      location: EU
      threads: 4
      timeout_seconds: 300
      priority: interactive
```

`method: oauth` uses the ADC from Task 2 Step 5. No key file exists, so no key file can leak.

- [ ] **Step 4: Install deps and verify the connection**

```powershell
cd C:\equities-dbt-bigquery
& .\.venv\Scripts\dbt.exe deps
& .\.venv\Scripts\dbt.exe debug
```

Expected: `All checks passed!`

- [ ] **Step 5: Copy the CSVs in as seeds**

```powershell
Copy-Item C:\quant_trading\reports\full_3527_setups.csv          C:\equities-dbt-bigquery\seeds\setups.csv
Copy-Item C:\quant_trading\reports\full_3527_backtest_results.csv C:\equities-dbt-bigquery\seeds\backtest_results.csv
```

- [ ] **Step 6: `seeds/_seeds.yml`**

```yaml
version: 2

seeds:
  - name: setups
    description: >
      909 candidate parabolic setups from the V5 relaxed scanner, 2020-07-27 to 2024-12-30.
      IN-SAMPLE. Walk-forward out-of-sample validation pending. Static reference data, version
      controlled with the project -- which is exactly what seeds are for.
    config:
      column_types:
        symbol: string
        date: date

  - name: backtest_results
    description: >
      Outcome per candidate setup: trades taken, PnL, win/loss. 909 rows, of which 327 were
      actually traded and 258 won (78.9% win rate on executed trades). IN-SAMPLE.
      Produced by the tick-based V5 engine, NOT by this dbt project. See spec 5.1.
    config:
      column_types:
        symbol: string
        date: date
```

- [ ] **Step 7: Load the seeds**

```powershell
& .\.venv\Scripts\dbt.exe seed
```

Expected: two `SUCCESS` lines, 909 rows each.

- [ ] **Step 8: `models/staging/_alpaca__sources.yml`**

```yaml
version: 2

sources:
  - name: alpaca
    database: "{{ env_var('GCP_PROJECT_ID') }}"
    schema: equities_raw
    description: >
      Raw 1-minute OHLCV bars loaded from the parabolic-reversal-trading-engine parquet cache.
      573 symbols -- every symbol that produced a setup -- full history, 20,391,519 rows.
    tables:
      - name: bars_1min
        description: >
          One row per minute per symbol, as Alpaca sent it. Bars are SPARSE: micro-caps only
          produce a bar when a trade occurs, so a symbol may have a few thousand bars across
          2019-2024 rather than 390/day. Do not assume a dense grid.
        columns:
          - name: timestamp
            description: Bar open time, UTC. Partition key.
          - name: symbol
            description: Ticker. Clustering key.
          - name: vwap
            description: >
              PER-BAR VWAP as sent by Alpaca -- one minute's worth. This is NOT session VWAP.
              Session VWAP is computed in int_bars_session_vwap. Do not confuse them.
```

- [ ] **Step 9: Commit**

```bash
cd /c/equities-dbt-bigquery && git add -A && git commit -m "feat(dbt): scaffold project, sources, seeds"
```

---

### Task 6: Staging layer + tests + EXPLAIN-BACK GATE

**Files:**
- Create: `models/staging/stg_alpaca__bars_1min.sql`, `stg_backtest__setups.sql`,
  `stg_backtest__results.sql`, `_staging__models.yml`, `tests/assert_no_malformed_bars.sql`

**Interfaces:**
- Consumes: `source('alpaca','bars_1min')`, `ref('setups')`, `ref('backtest_results')`
- Produces: `stg_alpaca__bars_1min(bar_key, symbol, bar_ts_utc, bar_ts_et, session_date,
  bar_time_et, open_price, high_price, low_price, close_price, volume, bar_vwap, session_phase)`;
  `stg_backtest__setups(symbol, setup_date, gain_pct, days_up, prior_gain, setup_volume, ...)`;
  `stg_backtest__results(symbol, setup_date, trades, pnl, is_win, is_loss, ...)`

- [ ] **Step 1: EXPLAIN FIRST — Claude explains, Brian confirms, before any SQL is written**

Cover: why staging is a view; why `bar_key` is a surrogate key rather than `(symbol, timestamp)`;
why there is **no** `WHERE` clause dropping bad bars (source profiled clean — a filter would hide
future garbage); why `bar_vwap` is renamed rather than dropped (source fidelity) but must never be
mistaken for session VWAP. Do not proceed until Brian confirms.

- [ ] **Step 2: `models/staging/stg_alpaca__bars_1min.sql`**

```sql
{{ config(materialized='view') }}

-- One row per 1-minute bar, exactly as Alpaca sent it: cast, renamed, and given ET session
-- context. NO filtering -- the source was profiled clean (0 malformed bars, 0 nulls, 0 dupes
-- across 20,391,519 rows on 2026-07-17), so a filter here would only hide future garbage.
-- The tests are the mechanism for that, not a WHERE clause.

with source as (

    select * from {{ source('alpaca', 'bars_1min') }}

),

renamed as (

    select
        {{ dbt_utils.generate_surrogate_key(['symbol', 'timestamp']) }} as bar_key,

        symbol,
        timestamp                                     as bar_ts_utc,
        datetime(timestamp, 'America/New_York')       as bar_ts_et,
        date(timestamp, 'America/New_York')           as session_date,
        time(datetime(timestamp, 'America/New_York')) as bar_time_et,

        open   as open_price,
        high   as high_price,
        low    as low_price,
        close  as close_price,
        volume,

        -- Alpaca's PER-BAR vwap (one minute). NOT session VWAP -- see int_bars_session_vwap.
        vwap   as bar_vwap,

        case
            when time(datetime(timestamp, 'America/New_York')) >= time '09:30:00'
             and time(datetime(timestamp, 'America/New_York')) <  time '16:00:00' then 'regular'
            when time(datetime(timestamp, 'America/New_York')) >= time '04:00:00'
             and time(datetime(timestamp, 'America/New_York')) <  time '09:30:00' then 'premarket'
            else 'postmarket'
        end                                           as session_phase

    from source

)

select * from renamed
```

`America/New_York` (never a fixed `-05:00`) so DST is handled by BigQuery, not by us.

- [ ] **Step 3: `models/staging/stg_backtest__setups.sql`**

```sql
{{ config(materialized='view') }}

with source as (

    select * from {{ ref('setups') }}

),

renamed as (

    select
        symbol,
        date                             as setup_date,
        cast(open   as float64)          as open_price,
        cast(high   as float64)          as high_price,
        cast(low    as float64)          as low_price,
        cast(close  as float64)          as close_price,
        cast(volume as int64)            as setup_volume,
        cast(gain_percent as float64) / 100.0 as gain_pct,   -- 66.5 -> 0.665
        cast(days_up as int64)           as days_up,
        cast(prior_gain as float64)      as prior_gain
    from source

)

select * from renamed
```

- [ ] **Step 4: `models/staging/stg_backtest__results.sql`**

```sql
{{ config(materialized='view') }}

with source as (

    select * from {{ ref('backtest_results') }}

),

renamed as (

    select
        symbol,
        date                             as setup_date,
        cast(gain_pct as float64) / 100.0 as gain_pct,
        cast(days_up as int64)           as days_up,
        cast(volume  as int64)           as setup_volume,
        cast(trades  as int64)           as trades,
        cast(pnl     as float64)         as pnl,
        cast(win  as int64) = 1          as is_win,
        cast(loss as int64) = 1          as is_loss
    from source

)

select * from renamed
```

- [ ] **Step 5: `models/staging/_staging__models.yml`**

```yaml
version: 2

models:
  - name: stg_alpaca__bars_1min
    description: >
      One row per 1-minute bar as Alpaca sent it, typed and renamed, with ET session context
      derived from the UTC timestamp. No filtering by design -- see model comment.
    columns:
      - name: bar_key
        description: Surrogate key over (symbol, timestamp). One row per bar.
        tests:
          - unique
          - not_null
      - name: symbol
        tests: [not_null]
      - name: bar_ts_utc
        tests: [not_null]
      - name: session_date
        description: ET calendar date. Derived, not inherited from the UTC partition key.
        tests: [not_null]
      - name: session_phase
        description: ET session bucket. Fires if the UTC->ET conversion ever drifts.
        tests:
          - accepted_values:
              values: ['premarket', 'regular', 'postmarket']

  - name: stg_backtest__setups
    description: 909 candidate setups. IN-SAMPLE; walk-forward pending.
    columns:
      - name: symbol
        tests:
          - not_null
          - relationships:
              to: ref('stg_alpaca__bars_1min')
              field: symbol
      - name: setup_date
        tests: [not_null]

  - name: stg_backtest__results
    description: Outcome per candidate setup, from the tick-based V5 engine. IN-SAMPLE.
    columns:
      - name: symbol
        tests: [not_null]
      - name: setup_date
        tests: [not_null]
```

- [ ] **Step 6: `tests/assert_no_malformed_bars.sql`**

```sql
-- DOMAIN RULE: a bar's low can never exceed its high, and open/close must sit inside [low, high].
-- Physically impossible in a real market. If this fires, Alpaca sent garbage or our load
-- corrupted the data.
--
-- Verified 0 violations across all 20,391,519 rows on 2026-07-17. It is GREEN today, by design:
-- a test is a contract, not a discovery. This is a tripwire nobody has tripped.

select
    bar_key,
    symbol,
    bar_ts_utc,
    open_price,
    high_price,
    low_price,
    close_price,
    volume
from {{ ref('stg_alpaca__bars_1min') }}
where low_price  > high_price
   or high_price < greatest(open_price, close_price)
   or low_price  > least(open_price, close_price)
   or volume     < 0
```

- [ ] **Step 7: Run and test**

```powershell
& .\.venv\Scripts\dbt.exe run  --select staging
& .\.venv\Scripts\dbt.exe test --select staging
```

Expected: 3 views built; all tests PASS. `unique` on `bar_key` passing confirms the load did not
double-insert.

- [ ] **Step 8: GATE — Brian explains the staging layer back in his own words**

He must answer without prompting:
1. Why is staging a view and not a table?
2. Why is there no `WHERE` filtering out bad bars?
3. What is `bar_key` and why not just use `(symbol, timestamp)`?
4. What would `accepted_values` on `session_phase` catch?

If any answer is shaky, re-explain and ask again. **Do not proceed on a nod.**

- [ ] **Step 9: Commit**

```bash
cd /c/equities-dbt-bigquery && git add -A && git commit -m "feat(staging): bars, setups, results + tripwire tests"
```

---

### Task 7: int_bars_session_vwap + EXPLAIN-BACK GATE

**Files:**
- Create: `models/intermediate/int_bars_session_vwap.sql`

**Interfaces:**
- Consumes: `ref('stg_alpaca__bars_1min')`
- Produces: `int_bars_session_vwap(bar_key, symbol, bar_ts_utc, bar_ts_et, session_date,
  bar_time_et, open_price, high_price, low_price, close_price, volume, typical_price,
  day_open, day_high, session_vwap, vwap_extension_ratio, day_gain)`

- [ ] **Step 1: EXPLAIN FIRST — the model Brian already made the call on**

Cover: why this is a **table** not a view (window over 20.4M rows, recomputed per downstream query
otherwise); why it re-partitions on ET `session_date` while the raw table partitions on UTC date;
how `rows between unbounded preceding and current row` anchors VWAP at the session's **first
available bar at/after 09:30** — which is what makes sparse micro-cap bars safe (there may be no
literal 09:30 bar); why `safe_divide` rather than `/`. Brian confirms before SQL is written.

- [ ] **Step 2: Write the model**

```sql
{{ config(
    materialized='table',
    partition_by={'field': 'session_date', 'data_type': 'date'},
    cluster_by=['symbol']
) }}

-- Session VWAP, anchored at 09:30 ET, cumulative through the regular session.
--
-- WHY INTERMEDIATE, NOT STAGING: `bar_vwap` exists because Alpaca sends it. `session_vwap`
-- exists because our strategy invented a 09:30 anchor. Vendor change -> fix staging. Strategy
-- change -> fix here. They never touch the same file.
--
-- ANCHORING: filtering to the regular session and framing UNBOUNDED PRECEDING -> CURRENT ROW
-- anchors on the FIRST BAR AT OR AFTER 09:30, not on a literal 09:30 bar. Micro-cap bars are
-- sparse -- a 09:30 bar frequently does not exist.
--
-- FIDELITY NOTE: V5 (v5_strict.py:75-89) anchors at the first bar of its TICK feed with no 09:30
-- filter. We anchor at 09:30 by explicit choice -- better defined, and matches documented intent.
-- This is one reason fct_signal_candidates cannot reproduce the tick backtest. See spec 5.1.

with regular_session as (

    select *
    from {{ ref('stg_alpaca__bars_1min') }}
    where session_phase = 'regular'

),

with_typical_price as (

    select
        *,
        -- (high + low + close) / 3, matching v5_strict.py:86
        (high_price + low_price + close_price) / 3.0 as typical_price
    from regular_session

),

cumulative as (

    select
        *,
        sum(typical_price * volume) over w_running as cum_tp_volume,
        sum(volume)                 over w_running as cum_volume,
        -- running max, inclusive of current bar -- matches v5_strict.py:93-94
        max(high_price)             over w_running as day_high,
        -- first bar's open for the session -- matches v5_strict.py:91-92
        first_value(open_price)     over w_session as day_open
    from with_typical_price
    window
        w_running as (
            partition by symbol, session_date
            order by bar_ts_utc
            rows between unbounded preceding and current row
        ),
        w_session as (
            partition by symbol, session_date
            order by bar_ts_utc
            rows between unbounded preceding and unbounded following
        )

)

select
    bar_key,
    symbol,
    bar_ts_utc,
    bar_ts_et,
    session_date,
    bar_time_et,
    open_price,
    high_price,
    low_price,
    close_price,
    volume,
    typical_price,
    day_open,
    day_high,

    safe_divide(cum_tp_volume, cum_volume)                    as session_vwap,
    -- close / vwap, matching v5_strict.py:150. Compared against 1.15 downstream.
    safe_divide(close_price, safe_divide(cum_tp_volume, cum_volume)) as vwap_extension_ratio,
    -- (day_high - day_open) / day_open, matching v5_strict.py:142
    safe_divide(day_high - day_open, day_open)                as day_gain

from cumulative
```

- [ ] **Step 3: Build it**

```powershell
& .\.venv\Scripts\dbt.exe run --select int_bars_session_vwap
```

- [ ] **Step 4: Sanity-check the VWAP against a known setup**

```bash
bq query --location=EU --use_legacy_sql=false --format=prettyjson \
 'SELECT bar_time_et, close_price, session_vwap, vwap_extension_ratio, day_gain
  FROM `'"${GCP_PROJECT_ID}"'.equities_intermediate.int_bars_session_vwap`
  WHERE symbol = "MNOV" AND session_date = "2020-07-27"
  ORDER BY bar_ts_utc LIMIT 5'
```

`MNOV` on 2020-07-27 is the first row of the setups CSV (66.5% gain). Expected: first bar's
`session_vwap` ≈ its own typical price (nothing has accumulated yet); `vwap_extension_ratio` near
1.0 early; `day_gain` rising through the session. If `session_vwap` is NULL, `cum_volume` is 0 —
investigate rather than paper over.

- [ ] **Step 5: GATE — Brian explains this model back**

1. Why is this a table when staging is a view?
2. Why partition on `session_date` here when the raw table partitions on UTC date?
3. Where exactly is the VWAP anchored, and why does that work when no 09:30 bar exists?
4. Why can't this model reproduce the tick backtest's numbers?

**This is the model he will be asked about.** Do not proceed on a nod.

- [ ] **Step 6: Commit**

```bash
cd /c/equities-dbt-bigquery && git add -A && git commit -m "feat(intermediate): session VWAP anchored 09:30 ET"
```

---

### Task 8: int_bars_exhaustion, int_session_features, int_setup_outcomes

**Files:**
- Create: `models/intermediate/int_bars_exhaustion.sql`, `int_session_features.sql`,
  `int_setup_outcomes.sql`, `_intermediate__models.yml`

**Interfaces:**
- Consumes: `ref('int_bars_session_vwap')`, `ref('stg_backtest__setups')`, `ref('stg_backtest__results')`
- Produces: `int_bars_exhaustion(..., vol_peak_10, volume_ratio, proximity_to_high,
  meets_vwap_extension, meets_volume_exhaustion, meets_proximity, criteria_met)`;
  `int_session_features(symbol, session_date, bar_count, session_volume,
  max_vwap_extension_ratio, max_day_gain, peak_extension_ts_et, bars_meeting_2of3)`;
  `int_setup_outcomes(symbol, setup_date, gain_pct, days_up, prior_gain, trades, pnl,
  is_candidate, is_traded, is_winner)`

- [ ] **Step 1: EXPLAIN FIRST** — the 2-of-3 criteria and why thresholds are frozen literals with
  source-line citations rather than variables to be tuned. Brian confirms.

- [ ] **Step 2: `models/intermediate/int_bars_exhaustion.sql`**

```sql
{{ config(materialized='view') }}

-- V5's 2-of-3 entry criteria, evaluated per bar.
-- THRESHOLDS ARE FROZEN at v5_strict.py:47-50. They are NOT tuning knobs. If our signal count
-- disagrees with the tick backtest, that is a finding to explain -- never a number to adjust.
-- See spec 5.1.

with base as (

    select * from {{ ref('int_bars_session_vwap') }}

),

with_vol_peak as (

    select
        *,
        -- max volume over the last 10 bars INCLUDING current -- matches v5_strict.py:124-127,
        -- where volume_history is appended-then-capped at 10 before vol_peak is taken.
        max(volume) over (
            partition by symbol, session_date
            order by bar_ts_utc
            rows between 9 preceding and current row
        ) as vol_peak_10
    from base

),

criteria as (

    select
        *,
        safe_divide(volume, vol_peak_10)   as volume_ratio,       -- v5_strict.py:151
        safe_divide(close_price, day_high) as proximity_to_high,  -- v5_strict.py:152

        vwap_extension_ratio                >= 1.15 as meets_vwap_extension,     -- :47, :155
        safe_divide(volume, vol_peak_10)    <= 0.70 as meets_volume_exhaustion,  -- :48, :156
        safe_divide(close_price, day_high)  >= 0.93 as meets_proximity           -- :49, :157

    from with_vol_peak

)

select
    *,
    -- v5_strict.py:154-158
    cast(meets_vwap_extension    as int64)
  + cast(meets_volume_exhaustion as int64)
  + cast(meets_proximity         as int64) as criteria_met
from criteria
```

- [ ] **Step 3: `models/intermediate/int_session_features.sql`**

```sql
{{ config(materialized='table') }}

-- Bar-grain -> session-grain. This is the fork: fct_signal_candidates keeps bar grain, while
-- fct_setup_funnel needs one row per (symbol, session_date) to join onto a setup.

select
    symbol,
    session_date,

    count(*)                                  as bar_count,
    sum(volume)                               as session_volume,
    max(vwap_extension_ratio)                 as max_vwap_extension_ratio,
    max(day_gain)                             as max_day_gain,
    max(day_high)                             as day_high,
    min(day_open)                             as day_open,
    min(bar_ts_et)                            as first_bar_ts_et,
    max(bar_ts_et)                            as last_bar_ts_et,

    -- timestamp of the most-extended bar of the session
    array_agg(bar_ts_et order by vwap_extension_ratio desc limit 1)[offset(0)]
                                              as peak_extension_ts_et,

    max(criteria_met)                         as max_criteria_met,
    countif(criteria_met >= 2)                as bars_meeting_2of3

from {{ ref('int_bars_exhaustion') }}
group by symbol, session_date
```

- [ ] **Step 4: `models/intermediate/int_setup_outcomes.sql`**

```sql
{{ config(materialized='view') }}

-- The funnel, made explicit: candidate -> traded -> won.
-- 909 candidates, 327 traded, 258 won. The 78.9% headline is 258/327 -- win rate conventionally
-- uses EXECUTED trades. The denominator is surfaced on purpose rather than hidden behind a
-- single number. IN-SAMPLE; walk-forward pending.

with setups as (

    select * from {{ ref('stg_backtest__setups') }}

),

results as (

    select * from {{ ref('stg_backtest__results') }}

)

select
    s.symbol,
    s.setup_date,
    s.gain_pct,
    s.days_up,
    s.prior_gain,
    s.setup_volume,

    r.trades,
    r.pnl,
    r.is_win,

    -- funnel stages
    true                                             as is_candidate,
    coalesce(r.trades > 0, false)                    as is_traded,
    coalesce(r.trades > 0 and r.is_win, false)       as is_winner

from setups s
left join results r
    on  s.symbol     = r.symbol
    and s.setup_date = r.setup_date
```

- [ ] **Step 5: `models/intermediate/_intermediate__models.yml`**

```yaml
version: 2

models:
  - name: int_bars_exhaustion
    description: >
      V5's 2-of-3 entry criteria per bar. Thresholds frozen at v5_strict.py:47-50.
    columns:
      - name: bar_key
        tests: [unique, not_null]
      - name: criteria_met
        description: Count of the 2-of-3 criteria met (0-3). Entry requires >= 2.
        tests:
          - accepted_values:
              values: [0, 1, 2, 3]
              quote: false

  - name: int_session_features
    description: Bar-grain aggregated to (symbol, session_date) for the funnel join.
    tests:
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns: [symbol, session_date]
    columns:
      - name: symbol
        tests: [not_null]
      - name: session_date
        tests: [not_null]

  - name: int_setup_outcomes
    description: >
      909 candidates -> 327 traded -> 258 won. IN-SAMPLE; walk-forward pending.
    tests:
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns: [symbol, setup_date]
    columns:
      - name: symbol
        tests: [not_null]
      - name: setup_date
        tests: [not_null]
```

- [ ] **Step 6: Run and test**

```powershell
& .\.venv\Scripts\dbt.exe run  --select intermediate
& .\.venv\Scripts\dbt.exe test --select intermediate
```

- [ ] **Step 7: Verify the funnel reproduces the known numbers exactly**

```bash
bq query --location=EU --use_legacy_sql=false --format=csv \
 'SELECT COUNT(*) AS candidates, COUNTIF(is_traded) AS traded, COUNTIF(is_winner) AS won,
         ROUND(100 * COUNTIF(is_winner) / NULLIF(COUNTIF(is_traded), 0), 1) AS win_rate_pct
  FROM `'"${GCP_PROJECT_ID}"'.equities_intermediate.int_setup_outcomes`'
```

Expected **exactly**: `909,327,258,78.9`. This model reads the backtest CSV, so it MUST match. If
it doesn't, the seed load or the join is wrong. (Contrast: `fct_signal_candidates` in Task 9 must
NOT be expected to match — different input data entirely.)

- [ ] **Step 8: Commit**

```bash
cd /c/equities-dbt-bigquery && git add -A && git commit -m "feat(intermediate): 2-of-3 criteria, session features, setup funnel"
```

---

### Task 9: fct_signal_candidates + market-hours test + EXPLAIN-BACK GATE

**Files:**
- Create: `models/marts/fct_signal_candidates.sql`, `_marts__models.yml`,
  `tests/assert_signals_within_market_hours.sql`

**Interfaces:**
- Consumes: `ref('int_bars_exhaustion')`
- Produces: `fct_signal_candidates(bar_key, symbol, session_date, bar_ts_utc, bar_ts_et,
  bar_time_et, close_price, volume, session_vwap, vwap_extension_ratio, volume_ratio,
  proximity_to_high, day_open, day_high, day_gain, meets_*, criteria_met, setup_rank,
  is_best_setup_of_day)`

- [ ] **Step 1: EXPLAIN FIRST** — why all qualifying bars are kept with `is_best_setup_of_day`
  flagged, rather than filtering to rank 1 (V5 takes one position/day, but a *candidates* mart
  that silently drops candidates is lying about its own name). Brian confirms.

- [ ] **Step 2: `models/marts/fct_signal_candidates.sql`**

```sql
{{ config(
    materialized='table',
    partition_by={'field': 'session_date', 'data_type': 'date'},
    cluster_by=['symbol']
) }}

-- V5's documented entry rules, REIMPLEMENTED IN SQL over Alpaca 1-minute bars.
--
-- THIS IS NOT A REPRODUCTION OF THE BACKTEST. The V5 engine (v5_strict.py:65-69) runs on TICK
-- data aggregated to 60s bars and anchors VWAP at its first tick bar; this runs on Alpaca
-- 1-minute bars anchored at 09:30 ET. Counts WILL differ, by construction. The two are NOT a
-- validation of each other. See spec 5.1.
--
-- Thresholds frozen at v5_strict.py:47-50. Never tuned to close a gap.

with eligible as (

    select *
    from {{ ref('int_bars_exhaustion') }}
    where bar_time_et between time '09:45:00' and time '14:00:00'  -- v5_strict.py:138 (inclusive)
      and day_gain    >= 0.50                                       -- v5_strict.py:143
      and close_price >= session_vwap                               -- v5_strict.py:146
      and criteria_met >= 2                                         -- v5_strict.py:160

),

ranked as (

    select
        *,
        -- V5 takes the highest-extension setup, max 1 position/day (v5_strict.py:161-162, 177).
        -- We keep every candidate and FLAG the best rather than dropping the rest -- a
        -- "candidates" mart that hides candidates would be misnamed.
        row_number() over (
            partition by symbol, session_date
            order by vwap_extension_ratio desc, bar_ts_utc asc
        ) as setup_rank
    from eligible

)

select
    bar_key,
    symbol,
    session_date,
    bar_ts_utc,
    bar_ts_et,
    bar_time_et,

    close_price,
    volume,
    session_vwap,
    vwap_extension_ratio,
    volume_ratio,
    proximity_to_high,
    day_open,
    day_high,
    day_gain,

    meets_vwap_extension,
    meets_volume_exhaustion,
    meets_proximity,
    criteria_met,

    setup_rank,
    setup_rank = 1 as is_best_setup_of_day

from ranked
```

- [ ] **Step 3: `tests/assert_signals_within_market_hours.sql`**

```sql
-- DOMAIN RULE: V5 only enters between 09:45 and 14:00 ET (v5_strict.py:138).
--
-- A signal outside that window means the UTC->ET conversion drifted. That is the single most
-- likely real bug in this project: EVERY source timestamp is UTC, every threshold is ET, and
-- DST moves the offset twice a year. SQL cannot infer this rule -- it has to be asserted.

select
    bar_key,
    symbol,
    session_date,
    bar_ts_utc,
    bar_ts_et,
    bar_time_et
from {{ ref('fct_signal_candidates') }}
where bar_time_et < time '09:45:00'
   or bar_time_et > time '14:00:00'
```

- [ ] **Step 4: `models/marts/_marts__models.yml`**

```yaml
version: 2

models:
  - name: fct_signal_candidates
    description: >
      One row per bar where V5's 2-of-3 entry criteria are met, computed in SQL from raw
      1-minute bars. REIMPLEMENTATION, not a reproduction of the tick-based backtest -- counts
      differ by construction and the two do not validate each other. Thresholds frozen at
      v5_strict.py:47-50. IN-SAMPLE; walk-forward pending.
    columns:
      - name: bar_key
        tests: [unique, not_null]
      - name: symbol
        tests: [not_null]
      - name: session_date
        tests: [not_null]
      - name: criteria_met
        tests:
          - accepted_values:
              values: [2, 3]
              quote: false
      - name: is_best_setup_of_day
        tests: [not_null]
```

`criteria_met` accepting only `[2, 3]` is a second, free tripwire: this mart filters `>= 2`, so a
0 or 1 appearing here would mean the filter broke.

- [ ] **Step 5: Run and test**

```powershell
& .\.venv\Scripts\dbt.exe run  --select fct_signal_candidates
& .\.venv\Scripts\dbt.exe test --select fct_signal_candidates
```

- [ ] **Step 6: Record the divergence as a FINDING — do not react to it**

```bash
bq query --location=EU --use_legacy_sql=false --format=csv \
 'SELECT COUNT(*) AS candidate_bars, COUNT(DISTINCT symbol) AS symbols,
         COUNT(DISTINCT FORMAT("%s|%t", symbol, session_date)) AS symbol_days,
         COUNTIF(is_best_setup_of_day) AS best_setups
  FROM `'"${GCP_PROJECT_ID}"'.equities_marts.fct_signal_candidates`'
```

Whatever this returns, **write it down and explain it. Do not touch 1.15 / 0.70 / 0.93.** If
`best_setups` is far from 909, the reasons are known and legitimate: tick vs minute bars, a
different VWAP anchor, and the fact that the 909 came from a *scanner* pass this project does not
reimplement. This number goes in the README as a finding.

- [ ] **Step 7: GATE — Brian explains this mart back**

1. Why doesn't this match your backtest's 909, and why is that fine?
2. What would you say to "just adjust the threshold until it matches"?
3. What does `assert_signals_within_market_hours` catch that `accepted_values` can't?

- [ ] **Step 8: Commit**

```bash
cd /c/equities-dbt-bigquery && git add -A && git commit -m "feat(marts): signal candidates + market-hours tripwire"
```

---

### Task 10: fct_setup_funnel

**Files:**
- Create: `models/marts/fct_setup_funnel.sql`
- Modify: `models/marts/_marts__models.yml`

**Interfaces:**
- Consumes: `ref('int_setup_outcomes')`, `ref('int_session_features')`
- Produces: `fct_setup_funnel(symbol, setup_date, gain_pct, days_up, prior_gain, trades, pnl,
  is_candidate, is_traded, is_winner, funnel_stage, bar_count, session_volume,
  max_vwap_extension_ratio, max_day_gain, peak_extension_ts_et, bars_meeting_2of3, has_bar_data)`

- [ ] **Step 1: Write the model**

```sql
{{ config(materialized='table') }}

-- The headline story: 909 candidates -> 327 traded -> 258 won (78.9% on executed trades).
-- The funnel is the point. A single "79%" hides that 582 setups never triggered; this mart
-- refuses to hide it. IN-SAMPLE; walk-forward out-of-sample validation pending.
--
-- LEFT JOIN to session features, not INNER: a setup with no matching bar data must still appear
-- in the funnel. An inner join would silently shrink the denominator -- the exact dishonesty
-- this mart exists to prevent.

with outcomes as (

    select * from {{ ref('int_setup_outcomes') }}

),

session_features as (

    select * from {{ ref('int_session_features') }}

)

select
    o.symbol,
    o.setup_date,
    o.gain_pct,
    o.days_up,
    o.prior_gain,
    o.trades,
    o.pnl,

    o.is_candidate,
    o.is_traded,
    o.is_winner,

    case
        when o.is_winner then 'won'
        when o.is_traded then 'lost'
        else 'never_triggered'
    end                                    as funnel_stage,

    f.bar_count,
    f.session_volume,
    f.max_vwap_extension_ratio,
    f.max_day_gain,
    f.peak_extension_ts_et,
    f.bars_meeting_2of3,
    f.symbol is not null                   as has_bar_data

from outcomes o
left join session_features f
    on  o.symbol     = f.symbol
    and o.setup_date = f.session_date
```

- [ ] **Step 2: Add to `_marts__models.yml`**

```yaml
  - name: fct_setup_funnel
    description: >
      One row per candidate setup: 909 -> 327 traded -> 258 won. Enriched with session-level bar
      features. The denominator is surfaced on purpose. IN-SAMPLE; walk-forward pending.
    tests:
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns: [symbol, setup_date]
    columns:
      - name: symbol
        tests: [not_null]
      - name: setup_date
        tests: [not_null]
      - name: funnel_stage
        tests:
          - accepted_values:
              values: ['won', 'lost', 'never_triggered']
```

- [ ] **Step 3: Run, test, and verify the funnel survived the join**

```powershell
& .\.venv\Scripts\dbt.exe run  --select fct_setup_funnel
& .\.venv\Scripts\dbt.exe test --select fct_setup_funnel
```

```bash
bq query --location=EU --use_legacy_sql=false --format=csv \
 'SELECT funnel_stage, COUNT(*) AS n, COUNTIF(has_bar_data) AS with_bars, ROUND(SUM(pnl),2) AS pnl
  FROM `'"${GCP_PROJECT_ID}"'.equities_marts.fct_setup_funnel` GROUP BY funnel_stage ORDER BY n DESC'
```

Expected: `never_triggered=582`, `won=258`, `lost=69`; total 909. If the total is not 909, the
LEFT JOIN fanned out — a session-features duplicate. Fix the join, never the count.

- [ ] **Step 4: Commit**

```bash
cd /c/equities-dbt-bigquery && git add -A && git commit -m "feat(marts): setup funnel with session features"
```

---

### Task 11: Full run + dbt docs

- [ ] **Step 1: Clean full run from zero**

```powershell
& .\.venv\Scripts\dbt.exe build
```

`dbt build` runs seeds → models → tests in dependency order. Expected: all PASS. This is the
command that proves the whole DAG works from nothing.

- [ ] **Step 2: Generate and serve docs**

```powershell
& .\.venv\Scripts\dbt.exe docs generate
& .\.venv\Scripts\dbt.exe docs serve --port 8080
```

Opens the lineage graph at http://localhost:8080. **This is the artifact he shows people.**
Click through to `int_bars_session_vwap` and confirm it has two downstream consumers — visual
proof it is not an orphan.

- [ ] **Step 3: Screenshot the lineage graph** → `docs/lineage.png`, referenced from the README.

- [ ] **Step 4: Commit**

```bash
cd /c/equities-dbt-bigquery && git add -A && git commit -m "docs: lineage graph"
```

---

### Task 12: Looker Studio dashboard

- [ ] **Step 1: Grant Looker Studio access to `equities_marts` ONLY**

Not `equities_raw`, not `equities_staging`. Demonstrates the layer boundary is real and enforced,
not just naming.

- [ ] **Step 2: Build the dashboard** at https://lookerstudio.google.com — connect BigQuery →
`equities_marts`.

Charts:
1. **The funnel** — 909 → 327 → 258 as a bar/funnel chart. The centrepiece.
2. **Win rate by `days_up`** — from `fct_setup_funnel`.
3. **PnL distribution** — histogram of `pnl` where `is_traded`.
4. **Signal candidates over time** — count by `session_date` from `fct_signal_candidates`.
5. **Extension vs outcome** — `max_vwap_extension_ratio` vs `funnel_stage`.

- [ ] **Step 3: Put the caveat ON the dashboard, not in a footnote**

A text box, visible without scrolling:

> All figures IN-SAMPLE. Walk-forward out-of-sample validation in progress. Win rate is 258/327
> executed trades; 582 of 909 candidate setups never triggered an entry. `fct_signal_candidates`
> reimplements the strategy's entry rules on 1-minute bars — it does **not** reproduce, and does
> not validate, the tick-based backtest.

- [ ] **Step 4: Share** → "Anyone with the link can view". Record the URL for the README.

---

### Task 13: README

- [ ] **Step 1: Write `README.md`** — skimmable by a recruiter in 30 seconds, drillable by an
engineer for 30 minutes. Must contain:

- One-line what-and-why; the lineage screenshot near the top
- Honest scope: *one dbt project over a 573-symbol / 20.4M-row subset* — **not** a claim of years
  of dbt fluency
- The measured numbers: 20,391,519 rows, 1.26 GB, €0.00
- The funnel: 909 → 327 → 258, in-sample, walk-forward pending — **stated before** any 78.9%
- The reimplementation boundary (spec 5.1) and the recorded divergence from Task 9 Step 6
- Partition-pruning bytes-scanned numbers from Task 4 Step 5
- Setup instructions that actually work on a clean machine
- Link to the Looker Studio dashboard and to INTERVIEW.md

- [ ] **Step 2: Commit**

```bash
cd /c/equities-dbt-bigquery && git add README.md && git commit -m "docs: README"
```

---

### Task 14: INTERVIEW.md — Brian's words

**This is the deliverable that gets him hired. Claude does NOT write the answers.**

- [ ] **Step 1: Claude creates the skeleton — questions only, no answers**

- [ ] **Step 2: Brian answers each, out loud first, then written, in his own words**

1. Walk me through your DAG.
2. Why is that model in intermediate and not marts?
3. What tests did you write, and why those?
4. What breaks if the source schema changes?
5. Why dbt instead of a folder of SQL scripts?
6. How does partitioning save you money here? *(use the measured bytes from Task 4 Step 5 — a
   guessed answer is worthless)*

- [ ] **Step 3: Claude critiques the answers — does not rewrite them**

Push where an interviewer would: "you said X — what if they ask Y?" Brian revises. The words stay
his.

- [ ] **Step 4: Record honestly what he did not walk through himself**

Per the brief, verbatim in INTERVIEW.md. If nothing, say that.

- [ ] **Step 5: Commit + push to github.com/BColladoT**

```bash
cd /c/equities-dbt-bigquery
gh repo create equities-dbt-bigquery --public --source=. --remote=origin --push
```

---

## Self-Review

**Spec coverage:**

| spec section | task |
|---|---|
| §2 ground truth (py3.10, 1min_extended only) | Global Constraints, Task 1, Task 3 |
| §3 funnel 909→327→258 | Task 8 Step 7, Task 10 |
| §3 honesty / in-sample qualifier | Tasks 5, 8, 9, 10, 12, 13 |
| §4 scope: 573 symbols, 20.4M rows | Task 3 |
| §5 layer rule | Tasks 6, 7, 8, 9, 10 |
| §5 VWAP ownership argument | Task 7 Steps 1, 5 |
| §5.1 frozen thresholds | Task 8 Step 2, Task 9 Step 6 |
| §5.1 reimplementation boundary | Task 9 Steps 2, 6, 7; Tasks 12, 13 |
| §6 nine models | Tasks 6–10 |
| §6 two partition keys | Task 4 Step 2, Task 7 Step 2 |
| §7 all six tests | Task 6 (unique/not_null/accepted_values/relationships/malformed), Task 9 (market hours) |
| §7 tests-as-tripwires | Task 6 Step 6 comment |
| §8 cost, budget alert first | Task 2 Step 4, Task 3 Step 3, Task 4 Step 5 |
| §9 deliverables 1–5 | Tasks 11, 12, 13, 14 |
| §10 env plan | Tasks 1, 2 |
| §11 sparse-bar anchor | Task 7 Steps 1, 2 |
| §11 DST | Task 6 Step 2 (`America/New_York`) |

No gaps.

**Placeholder scan:** none. Every step carries the real command or the real code.

**Type consistency:** `bar_key` / `session_date` / `bar_ts_utc` / `bar_ts_et` / `bar_time_et` /
`vwap_extension_ratio` / `criteria_met` / `is_best_setup_of_day` / `funnel_stage` are used
identically wherever they appear (Tasks 6→7→8→9→10). `int_setup_outcomes` joins on `setup_date`;
`int_session_features` exposes `session_date`; the join in Task 10 maps them explicitly
(`o.setup_date = f.session_date`) rather than assuming a shared name.

## Execution model

Inline, in this session, with the explain-back gates in Tasks 6, 7, 8, 9 honoured. **Not**
subagent-driven — see the header. Two days owned beats two hours delivered.
