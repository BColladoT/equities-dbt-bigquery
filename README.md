# equities-dbt-bigquery

A dbt Core project that models **20.4M rows of 1-minute equity bars** into a signal-candidate mart
and a setup funnel — staging → intermediate → marts, 9 models, 53 tests, two warehouse targets.

Built on real data from my own [parabolic-reversal trading engine](https://github.com/BColladoT/parabolic-reversal-trading-engine):
573 micro-cap symbols, 2020–2024.

---

## Read this first — scope, honestly stated

This is **one dbt project over a subset of my own data**. It is not two years of dbt in
production, and nothing here should be read that way.

| | status |
|---|---|
| **dbt DAG, models, tests, docs** | ✅ built and running |
| **`dbt build`** | ✅ **52 pass, 0 errors, 1 expected warning** (DuckDB dev target) |
| **DuckDB dev target** | ✅ runs today, on any machine, no cloud account needed |
| **BigQuery prod target** | ⚙️ **configured, NOT yet run** — no GCP project exists yet |
| **Looker Studio dashboard** | ❌ not built — depends on BigQuery |
| **All metrics below** | ⚠️ **IN-SAMPLE.** Walk-forward out-of-sample validation in progress. |

The BigQuery target is real code — partitioning, clustering, the `bq load` script, the 573-symbol
subset builder — but it has **never been executed**, because that needs a billed Google Cloud
account. Saying "BigQuery" while having never run a query against it would be a lie, so: it is
configured and unrun. That gets fixed by creating the project, not by rewording this table.

## The numbers, with the denominator attached

```
909 candidate setups  →  327 actually traded  →  258 wins  =  78.9% win rate
                         582 never triggered an entry
```

**78.9% is the win rate on executed trades** — which is how win rate is conventionally computed,
and it is correct. But 582 of 909 candidates (64%) never triggered at all, and that number belongs
next to the headline rather than behind it. `fct_setup_funnel` surfaces all three stages as
columns for exactly this reason.

**IN-SAMPLE. Walk-forward out-of-sample validation is in progress.** These are not live, audited,
or validated results.

## The DAG

```
SOURCES              STAGING (views)          INTERMEDIATE                MARTS (tables)
                     source-shaped only       strategy logic              what BI reads

bars_1min  ──►  stg_alpaca__bars_1min  ──►  int_bars_session_vwap  ──┐
20.4M prod      cast, UTC→ET, session        09:30 ET anchor,        │
220k dev        phase. NO filtering.         cumulative VWAP          │
                                                      │              │
                                                      ▼              │
                                              int_bars_exhaustion ───┼──► fct_signal_candidates
                                              V5's 2-of-3 criteria   │    bar grain, signal fires
                                                      │              │
                                                      ▼              │
                                              int_session_features   │
                                              → (symbol, session_date)
                                                      │
setups.csv ──►  stg_backtest__setups  ──┐             │
909 seed                                ├──► int_setup_outcomes ─────┴──► fct_setup_funnel
results.csv ─►  stg_backtest__results ──┘    candidate→traded→won         909→327→258
909 seed
```

`dbt docs generate && dbt docs serve` for the interactive lineage graph.

### The layer rule

- **staging** — *"what does the source say?"* One model per source, 1:1 rows, rename + cast. No
  joins, no business logic.
- **intermediate** — the bridge. Logic several marts need, that would make a mart unreadable
  inlined. Nobody queries it directly.
- **marts** — *"what does the business ask?"* Grain is a business entity.

### Why session VWAP is intermediate, not staging

Row grain doesn't settle it — it's one row per bar either way. **Ownership** does:

> `bar_vwap` exists because **Alpaca** sends it. `session_vwap` exists because **my strategy**
> invented a 09:30 anchor. Vendor changes their feed → I fix staging. I move my anchor to
> premarket → I fix intermediate. They never touch the same file.

## Two targets, one codebase

| target | engine | data | status |
|---|---|---|---|
| `dev` | DuckDB | committed 10-symbol sample (220,388 real rows, 5.1 MB) | runs today |
| `prod` | BigQuery | 573 symbols, 20,391,519 rows, 1.26 GB | configured, unrun |

```bash
dbt build              # dev — works immediately after `dbt deps`, no credentials
dbt build --target prod   # needs a GCP project + the bq load (see load/)
```

The sample is **real data, not synthetic**, and deliberately spans all three funnel branches
(59 setups: 24 traded, 19 won) so the marts are genuinely exercised. It's committed so that
`dbt build` works for anyone who clones this — including you, right now.

SQL is portable across both engines: `a / nullif(b,0)` rather than BigQuery's `safe_divide()`,
`sum(case when …)` rather than `countif()`, a ranked window rather than
`array_agg(…)[offset(0)]`. Timezone conversion is the one place the engines genuinely disagree,
so it lives in a single macro (`macros/to_et.sql`) — **never a hardcoded UTC offset**, because
New York is UTC-5 in winter and UTC-4 in summer and hardcoding either silently shifts every bar
by an hour for half the year.

## Finding: SQL signals vs the tick backtest disagree ~42% of the time

`fct_signal_candidates` **reimplements** the strategy's entry rules in SQL. It does **not**
reproduce the original backtest, and the two do **not** validate each other:

| | tick backtest | this project |
|---|---|---|
| input | tick trades → 60s bars | Alpaca 1-minute bars |
| VWAP anchor | first bar of the tick feed | **09:30 ET** (explicit choice) |
| engine | Python | SQL |

Measured on the 10 sample symbols:

```
tick backtest setups : 59
our SQL signal days  : 53
        BOTH agree   : 34      ← 57.6% overlap
     backtest only   : 25      tick data saw setups our minute bars didn't
          SQL only   : 19      our minute bars fired where the scanner never looked
```

**The totals lie.** 53 vs 59 looks like near-agreement; only 34 actually match. Comparing counts
instead of sets would have hidden a ~42% disagreement running in *both* directions.

Thresholds are **frozen** at the engine's own values (`v5_strict.py:47-50`): `close/vwap >= 1.15`,
`volume/vol_peak <= 0.70`, `close/day_high >= 0.93`, `day_gain >= 0.50`, entry window 09:45–14:00
ET. They are **not** tuning knobs. Nudging them until 53 became 59 would have fitted the model to
the answer and made it worthless. The divergence is a finding, published as measured.

## Tests — 53 of them, and they're contracts, not discoveries

| test | catches |
|---|---|
| `unique` + `not_null` on `bar_key` | a re-run `bq load` double-inserting — **the one most likely to actually fire** |
| `accepted_values` on `session_phase` | UTC→ET conversion drift |
| `relationships` setups.symbol → bars.symbol | a setup whose symbol has no bars |
| `accepted_values` on `criteria_met` = [2,3] | a tripwire on this project's own `WHERE` clause |
| **singular: `assert_no_malformed_bars`** | `low > high` — physically impossible; vendor garbage |
| **singular: `assert_signals_within_market_hours`** | a signal at 03:00 ET = timezone bug |

**The source was profiled clean** before a line of SQL was written: 0 malformed bars, 0 nulls,
0 duplicate timestamps across all 20,391,519 rows. So staging does **not** filter — a `WHERE`
clause would fix rows silently, where a test fails loudly. Loud is the requirement.

Which means most of these tests are green on day one. That's the point: *a test is a contract,
not a discovery.* A test that has never failed is a tripwire nobody has tripped.

**The `relationships` test warns on dev and errors on prod**, and that asymmetry is deliberate:

```yaml
severity: "{{ 'error' if target.type == 'bigquery' else 'warn' }}"
```

On prod, the universe is *defined* as "every symbol that produced a setup", so a setup without
bars means the load dropped rows — a real error. On dev, the sample is deliberately 10 of 573
symbols, so ~850 setups have no bars **by construction**. The test still runs and still reports
them; it just doesn't assert something known to be false.

## Cost

| item | measured |
|---|---|
| prod storage | 1.26 GB (free tier: **10 GiB**) |
| one full scan | 0.0013 TiB → ~790 free full scans/month (free tier: **1 TiB/mo**) |
| **expected spend** | **€0.00** |

Partitioned by date, clustered by symbol from day one — good practice *and* what holds the bill at
zero. A €1 budget alert goes up before anything is loaded.

## What this project does not do

Stated so nobody has to discover it by reading the code:

- **Has not run on BigQuery.** The target is configured, not exercised.
- **No Looker Studio dashboard.** Depends on the above.
- **Does not validate the trading strategy.** It reports a backtest it did not run, and separately
  reimplements the entry rules — the two disagree ~42% of the time and neither confirms the other.
- **Does not test the timezone macro against DST boundaries.** The conversion is defended by
  construction (one call site, no hardcoded offsets, engine-native tz tables). Verifying it
  properly needs a fixture of known DST-boundary timestamps with expected ET values. Worth doing.
  Not done.
- **Does not reimplement the scanner** that produced the 909 candidates — only the entry rules.
- **Metrics are in-sample.** Walk-forward validation is in progress in the engine repo.

## Repo layout

```
models/staging/        3 views  — source-shaped, no business logic
models/intermediate/   4 models — session VWAP, 2-of-3 criteria, session features, funnel
models/marts/          2 tables — fct_signal_candidates, fct_setup_funnel
tests/                 2 singular tests encoding domain rules SQL can't infer
macros/to_et.sql       the one place the two engines disagree
seeds/                 909 setups + 909 backtest results (static, version-controlled)
load/build_subset.py   --full (573 symbols → bq load) | --sample (10 symbols → committed)
load/load_to_bq.sh     bq load, partitioned + clustered
data/sample/           220,388 real rows so `dbt build` works on a fresh clone
docs/superpowers/      the design spec and the 14-task build plan, including what changed and why
```

## Running it

```bash
python -m venv .venv && .venv/Scripts/pip install -r requirements.txt
.venv/Scripts/dbt deps
.venv/Scripts/dbt build          # DuckDB — no credentials needed
.venv/Scripts/dbt docs generate && .venv/Scripts/dbt docs serve
```

## See also

- [`INTERVIEW.md`](INTERVIEW.md) — my own answers on why this is built the way it is
- [`docs/superpowers/specs/`](docs/superpowers/specs/) — the design, including four assumptions
  that measurement disproved
- [`docs/superpowers/plans/`](docs/superpowers/plans/) — the build plan
