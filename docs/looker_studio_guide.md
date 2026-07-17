# Looker Studio dashboard — build guide

Everything upstream is done: the marts are live in BigQuery (`equities_marts.fct_setup_funnel` and
`equities_marts.fct_signal_candidates`), partitioned, clustered, tested. This is the last step, and
it has to be done in your Google account — nobody can log in as you, which is why it isn't
automated.

Budget: ~10–15 minutes. You will connect two tables, drop in five charts, add one caveat box, and
share.

---

## Step 0 — open a report already connected to your data

Click this (signed in as brian.collado7@gmail.com). It opens a **new Looker Studio report with both
marts pre-connected** via the Looker Studio Linking API, so you skip the "add data source" dance:

```
https://lookerstudio.google.com/reporting/create?c.reportId=CREATE&ds.ds0.connector=bigQuery&ds.ds0.type=TABLE&ds.ds0.projectId=quant-trading-502717&ds.ds0.datasetId=equities_marts&ds.ds0.tableId=fct_setup_funnel&ds.ds0.billingProjectId=quant-trading-502717&ds.ds1.connector=bigQuery&ds.ds1.type=TABLE&ds.ds1.projectId=quant-trading-502717&ds.ds1.datasetId=equities_marts&ds.ds1.tableId=fct_signal_candidates&ds.ds1.billingProjectId=quant-trading-502717
```

If it asks to authorize the BigQuery connector, allow it (this is your own project). `ds0` is the
funnel; `ds1` is the signal candidates.

**Manual fallback** if the link misbehaves: New report → Add data → BigQuery → project
`quant-trading-502717` → dataset `equities_marts` → add `fct_setup_funnel`, then repeat for
`fct_signal_candidates`.

---

## Step 1 — the caveat box (do this FIRST, so it's never forgotten)

Insert → Text. Put it across the top. Paste verbatim — this is the honesty line the whole project
rests on:

> **All figures in-sample.** Walk-forward out-of-sample validation in progress. Win rate is
> 258/327 executed trades; 582 of 909 candidate setups never triggered. `fct_signal_candidates`
> reimplements the entry rules on 1-minute bars — it does **not** reproduce or validate the
> tick-based backtest (57.5% overlap).

## Step 2 — five charts

Grain matters: the first four read **fct_setup_funnel** (one row per setup); the fifth reads
**fct_signal_candidates** (one row per signal bar). Set each chart's data source explicitly.

1. **The funnel — the centrepiece.** Chart: Bar. Source: `fct_setup_funnel`.
   - Dimension: `funnel_stage`
   - Metric: `Record Count`
   - Sort descending. You'll see `never_triggered` 582, `won` 258, `lost` 69. Optionally reorder to
     candidate → traded → won with a manual sort. The point is that 582 is visibly the biggest bar.

2. **Win rate by `days_up`.** Chart: Bar or Table. Source: `fct_setup_funnel`.
   - Dimension: `days_up`
   - Metric: create a calculated field `win_rate` = `SUM(CAST(is_winner AS INT64)) / SUM(CAST(is_traded AS INT64))`, format as %.
   - Answers "does a longer prior run-up change the odds?"

3. **PnL distribution.** Chart: Histogram (or Bar by symbol). Source: `fct_setup_funnel`.
   - Metric: `pnl`, filtered to `is_traded = true`. Shows the spread of outcomes, not just the mean.

4. **Extension vs outcome.** Chart: Scatter. Source: `fct_setup_funnel`.
   - X: `max_vwap_extension_ratio`  Y: `pnl`  Colour: `funnel_stage`, filter `has_bar_data = true`.
   - The strategy's thesis is "fade the extension" — this is where you'd see it hold or not.

5. **Signals over time.** Chart: Time series. Source: `fct_signal_candidates`.
   - Dimension: `session_date`  Metric: `Record Count`, optionally filter `is_best_setup_of_day = true`.
   - Shows when the entry logic fired across 2020–2024.

## Step 3 — share

- Top-right **Share** → **Manage access** → General access → **Anyone with the link** → Viewer.
- Copy the link. Paste it into `README.md` where it says the dashboard is pending, and into the
  status table. Commit.

Sharing publicly is your call to make — it exposes the marts' aggregates (not the raw bars) to
anyone with the link. Given the data is your own micro-cap research and carries the in-sample
caveat, public-view is normally fine for a CV piece, but it's your decision to click.

---

## What to be ready to say about it

The dashboard is a presentation of the marts, nothing more — all the logic lives in dbt. If asked
"where does the win rate come from," the answer is `fct_setup_funnel`, not a Looker calculation:
the funnel stages are computed in SQL and tested, and Looker only counts them. That separation —
logic in the warehouse, presentation in BI — is itself the point.
