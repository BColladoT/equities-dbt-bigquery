# Design: dbt + BigQuery + Looker Studio over parabolic-reversal equities data

**Date:** 2026-07-17
**Owner:** Brian Collado
**Status:** Approved (design), not yet implemented

---

## 1. Why this exists

Close a specific, named skill gap: **dbt**. Eight job evaluations converged on dbt being the last
hard gap for the data-analytics roles being targeted (Spanish banks, fintechs, asset managers).
There is strong adjacent evidence already — PostgreSQL schema design at 17M+ rows, Apache Spark
across 40GB+, Polars/Numba over 4.5 years x 700+ equities of 1-minute bars — and zero dbt.

The output goes on a CV. The binding constraint is therefore **not** "the code runs". It is:

> Brian can be walked through any model in this repo, under hostile questioning, for ten minutes
> without hesitating.

A smaller project fully owned beats a larger one that cannot be defended. Every design decision
below was explained and chosen by Brian before being written down, not generated and handed over.

## 2. Ground truth (measured 2026-07-17 — not assumed)

The original brief carried several assumptions that measurement contradicted. Recorded here
because "I verified rather than assumed" is itself part of the story.

| Claim in brief | Measured reality | Consequence |
|---|---|---|
| Dataset ~300M rows, ~15 GB raw | **104.8M rows, 1.39 GB parquet** (3,082 symbols) | Full dataset would fit free tier |
| Full dataset exceeds 10 GiB free storage | **~6.5 GB logical** | Premise for "30-50 tickers only" does not hold |
| `py` launcher broken | **Confirmed** — default `-V:3.11 *` points at deleted `Python311\python.exe` | Use Python 3.10 |
| — | **`python` on PATH resolves to `hermes-agent\venv`** (a foreign tool's venv) | Never `pip install` into it |
| — | **`C:\quant_trading\venv` is broken** — polars + pyarrow fail native DLL load | Do not attempt repair; not needed |
| — | **`data/cache/*.parquet` (root) are DAILY bars** despite `_1min_` in the filename | Trap: use `1min_extended/` only |
| — | Raw `vwap` column is **per-bar**, not session-anchored | Session VWAP must be computed, not read |

**Verified source schema** (`data/cache/1min_extended/*.parquet`, one file per symbol, no overlapping ranges):

| column | type |
|---|---|
| `timestamp` | `timestamp[us, tz=UTC]` |
| `open`, `high`, `low`, `close`, `volume`, `vwap` | `double` |
| `symbol` | `large_string` |

Bars are **sparse** — micro-caps only produce a bar when a trade occurs, so a symbol may have a
few thousand bars across 2019–2024 rather than 390/day. Models must not assume a dense grid.

## 3. The number this project reports

Backtest CSVs (`reports/full_3527_backtest_results.csv`, 909 rows, 2020-07-27 → 2024-12-30):

```
909 candidate setups  →  327 actually traded  →  258 wins  =  78.9% win rate
                         582 never triggered an entry
```

The **78.9%** figure is real and correctly computed — win rate conventionally uses executed
trades. But the denominator is the first thing a competent interviewer asks for. The marts layer
therefore surfaces the **funnel**, not the headline, on purpose.

### Honesty constraints (non-negotiable)

- All metrics are **IN-SAMPLE**. Walk-forward out-of-sample validation is **in progress**.
- Every surfaced number carries that qualifier — in the dashboard, the README, and verbally.
- Never present these as live, audited, or validated results.
- The CV line says *"a dbt project over a subset of my equities data"*, with a number. It does not
  say "dbt" in a way implying two years' fluency.

## 4. Scope decision

**Chosen: all 573 symbols that ever produced a setup, full history.**

| option | rows | BQ logical | setups covered | headline win rate |
|---|---|---|---|---|
| top-50 by setup count | 1.9M | 0.12 GB | 197/909 | 85.5% — **selection-biased** |
| **all 573 setup symbols** | **20.4M** | **1.26 GB** | **909/909** | **78.9% — the real one** |
| everything | 104.8M | 6.50 GB | 909/909 | 78.9% |

Rationale: still a subset (19% of rows), so it honours the brief's "start with a subset" intent,
but chosen by a **defensible rule** — *every symbol that ever produced a setup* — rather than an
arbitrary count. Critically, selecting the top-50 *by setup count* is a non-random filter that
inflates the win rate to 85.5%; that would require a third caveat on every dashboard number.

This knowingly overrides the brief's "~30-50 tickers over 12 months" instruction. The instruction's
stated rationale (storage + query quota) was based on the 15 GB estimate, which measurement
disproved. Flagged to Brian; he made the call.

## 5. Architecture

```
SOURCES            STAGING (views)          INTERMEDIATE (tables/views)   MARTS (tables)
                   source-shaped only       strategy logic lives here     what Looker reads

bars_1min ──► stg_alpaca__bars_1min ──► int_bars_session_vwap ──┬──► fct_signal_candidates
(20.4M, BQ)   cast, UTC→ET, session      9:30 ET anchor, cum     │     bar grain: signal fires
              phase, drop malformed      VWAP, extension %       │
                                                 │              │
                                                 ▼              │
                                         int_bars_exhaustion ───┘
                                         volume exhaustion factors
                                                 │
                                                 ▼
                                          int_session_features
                                          → (symbol, session_date) grain
                                                 │
setups.csv ──► stg_backtest__setups ──┐          │
(909, seed)                           ├──► int_setup_outcomes ──┴──► fct_setup_funnel
results.csv ─► stg_backtest__results ─┘    candidate→traded→won      909→327→258, enriched
(909, seed)
```

### The layer rule (the thing to be able to recite)

- **staging** — *"what does the source say?"* One model per source, 1:1 rows, rename + cast +
  clean. No joins, no business logic.
- **intermediate** — the bridge. Hard logic several marts need, that would make a mart unreadable
  if inlined. Nobody queries it directly.
- **marts** — *"what does the business ask?"* Grain is a business entity. This is what BI touches.

### Why session VWAP is intermediate, not staging

Row grain does **not** settle it — it is one row per bar either way. **Ownership** settles it:

> `vwap` exists because **Alpaca** sends it. `session_vwap` exists because **my strategy** invented
> a 9:30 anchor. If the vendor changes their feed I fix **staging**. If I move my anchor to
> premarket I fix **intermediate**. Keeping them apart means a vendor change and a strategy change
> never touch the same file.

General form: *staging is source-shaped and strategy-agnostic; the moment a column exists because
of you rather than the vendor, it moves downstream.*

### Why both marts exist (the orphan problem)

An earlier iteration had `fct_setup_funnel` as the only mart. That orphans
`int_bars_session_vwap` — nothing downstream reads it — leaving a live DAG over **1,818 CSV rows**
while 20.4M bars sit unused. That is the "folder of SQL scripts" dbt is meant to beat, and it
guts the answer to *"why is that model in intermediate and not marts?"* (an ingredient no mart
consumes is not an ingredient).

Resolution: `fct_signal_candidates` gives the bars pipeline a real consumer and makes dbt
**compute the strategy** rather than report a CSV of results Python already produced.
`int_session_features` additionally feeds session-level context onto the funnel.

## 6. Models

| model | layer | materialization | grain | reads from | purpose |
|---|---|---|---|---|---|
| `stg_alpaca__bars_1min` | staging | view | 1 bar | `source: bars_1min` | cast, rename, UTC→ET, `session_date`, `session_phase`, drop malformed |
| `stg_backtest__setups` | staging | view | 1 setup | `seed: setups` | typed; `gain_percent` → fraction |
| `stg_backtest__results` | staging | view | 1 setup | `seed: backtest_results` | typed; `win`/`loss` → boolean |
| `int_bars_session_vwap` | intermediate | **table**, partitioned by `session_date`, clustered by `symbol` | 1 bar | `stg_alpaca__bars_1min` | session VWAP anchored 9:30 ET; `vwap_extension_pct` |
| `int_bars_exhaustion` | intermediate | view | 1 bar | `int_bars_session_vwap` | volume-exhaustion factors (strategy needs ≥2); carries VWAP fields through |
| `int_session_features` | intermediate | table | (symbol, session_date) | `int_bars_exhaustion` | max extension, peak-extension time, session volume |
| `int_setup_outcomes` | intermediate | view | `stg_backtest__setups` ⋈ `stg_backtest__results` | (symbol, setup_date) | candidate/traded/won |
| `fct_signal_candidates` | marts | **table**, partitioned + clustered | 1 bar where signal fires | `int_bars_exhaustion` | dbt-computed signal from raw bars |
| `fct_setup_funnel` | marts | table | (symbol, setup_date) | `int_setup_outcomes` ⋈ `int_session_features` | 909→327→258 funnel + session features |

Read the chain top-to-bottom: bars flow `staging → session_vwap → exhaustion`, then **fork** —
one branch aggregates to session grain for the funnel, the other stays at bar grain for signal
candidates. The two CSV seeds join early and meet the bar branch only at `fct_setup_funnel`.

### Materialization reasoning

Staging = views (free, always fresh, no storage). Marts = tables (Looker hits them repeatedly; pay
once). The load-bearing decision is `int_bars_session_vwap`: a window function over 20.4M rows.
As a **view** that window recomputes on *every* downstream query — both marts, plus every dashboard
refresh. As a **table** it computes once per `dbt run`. Materializations will be adjusted based on
measured cost, not dogma.

### Two partition keys — not a contradiction

There are deliberately **two** differently-partitioned tables, and the difference is the point:

| table | partition key | why |
|---|---|---|
| raw `bars_1min` (loaded by `bq load`) | UTC `DATE(timestamp)` | loaded faithfully as the vendor sent it; ELT, not ETL — no transformation before load |
| `int_bars_session_vwap` (dbt) | ET `session_date` | how we actually query, so pruning aligns with our filters |

`stg_alpaca__bars_1min` is a **view**, so it has no partitions of its own — it derives ET
`session_date` from the raw UTC timestamp, and the first *materialized* thing downstream adopts
that as its partition key. This is why after-hours bars spilling across a UTC date boundary
(20:00 ET = 00:00 UTC next day) is a non-issue: the ET session date is recomputed, not inherited.

## 7. Tests

| test | type | model | catches |
|---|---|---|---|
| `unique` + `not_null` on `bar_key` | generic | `stg_alpaca__bars_1min` | duplicate loads — the #1 warehouse bug |
| `accepted_values` on `session_phase` | generic | `stg_alpaca__bars_1min` | `premarket/regular/postmarket`; fires if ET conversion drifts |
| `relationships` `setups.symbol` → `bars.symbol` | generic | `stg_backtest__setups` | a setup for a symbol with no bars |
| `not_null` on join keys | generic | `int_setup_outcomes` | silent join failure |
| **`assert_no_malformed_bars`** (`low > high`) | **singular** | staging | physically impossible — vendor sent garbage |
| **`assert_signals_within_market_hours`** | **singular** | `fct_signal_candidates` | timezone bugs — the most likely real failure |

The two singular tests encode **domain rules SQL cannot infer**. `low > high` cannot occur in a
real market. A signal at 03:00 ET means UTC→ET conversion broke — the highest-probability bug in
this project, since *every* source timestamp is UTC.

## 8. Cost

| item | estimate |
|---|---|
| upload | 291 MB parquet, one-time |
| storage | 1.26 GB logical (free tier: **10 GiB**) |
| one full scan of bars | 0.0013 TiB → ~790 free full scans/month (free tier: **1 TiB/mo**) |
| **expected spend** | **€0.00** |

Controls: billing budget alert set **before** any load. Partition by `session_date` + cluster by
`symbol` from day one — good practice *and* what holds the bill at zero. Never `SELECT *` on the
raw table. If any estimate stops being ~zero: stop and say so.

## 9. Deliverables

1. Working dbt project, repo under `github.com/BColladoT`.
2. `dbt docs generate` lineage graph, viewable.
3. Looker Studio dashboard, shareable link.
4. `README.md` — skimmable by a recruiter, drillable by an interviewer.
5. **`INTERVIEW.md`** — Brian's answers, **in his own words**, to:
   - Walk me through your DAG.
   - Why is that model in intermediate and not marts?
   - What tests did you write, and why those?
   - What breaks if the source schema changes?
   - Why dbt instead of a folder of SQL scripts?
   - How does partitioning save you money here?

Deliverable 5 is the one that gets him hired. It is **not** to be written for him. If any part of
the build is not walked through by Brian himself, that fact gets recorded in `INTERVIEW.md`.

## 10. Environment plan

- **Python 3.10** (`C:\Users\brian\AppData\Local\Programs\Python\Python310\python.exe`) is the
  dbt base. Verified working; a clean venv + pyarrow installs and imports.
- Dedicated venv for this repo. Never the hermes venv, never `C:\quant_trading\venv`.
- `dbt-core` + `dbt-bigquery`. dbt **Core**, not Cloud — free, and the mechanics are visible.
- `gcloud` CLI for auth (`gcloud auth application-default login`).
- Brian attaches billing himself. Card entry is never delegated.

## 11. Risks / open questions

| risk | mitigation |
|---|---|
| Sparse bars break session VWAP (no 9:30 bar exists) | Anchor on *first bar at/after 09:30 ET*, not on a literal 09:30 bar |
| UTC→ET across DST (EST/EDT) | Use BigQuery `America/New_York` tz conversion, never a fixed offset |
| After-hours bars spill to next UTC date | Raw partitioned by UTC `DATE(timestamp)`; `session_date` derived in ET in staging |
| `fct_signal_candidates` is circular if only setup dates are loaded | Full history for all 573 symbols is loaded, incl. non-setup days |
| Thresholds tuned to make signals match known setups | Thresholds come from the existing strategy registry (V5 relaxed), not fitted here |
| dbt-bigquery / Python 3.10 incompatibility | Verify at install; fall back to a fresh Python 3.12 if needed |

## 12. Out of scope

- Recomputing or re-validating the backtest itself. This project reports on it, honestly.
- Walk-forward out-of-sample validation (in progress elsewhere).
- The live trading engine, the RL pipeline, Ray/PPO outputs.
- Loading tick data (35k files) or the daily-bar root cache.
