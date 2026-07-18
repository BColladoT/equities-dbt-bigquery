# Looker Studio dashboard — exact build recipe

The marts are live in BigQuery (`equities_marts.fct_setup_funnel`, `equities_marts.fct_signal_candidates`),
partitioned, clustered, tested. The dashboard is a thin presentation layer over them — all the logic
lives in dbt. This recipe is the *exact* build that was assembled and verified once against the live
marts; every value below is what the charts actually showed. Rebuilding is a deterministic ~10-minute
job. It must be done signed in as brian.collado7@gmail.com — nobody can log in as you.

---

## Step 0 — create a report that ACTUALLY SAVES (read this first)

**The trap that cost the first build:** a report opened via the Linking API URL
(`lookerstudio.google.com/reporting/create?...`) is a *transient* draft. Its URL stays at
`/reporting/create` and it is **never persisted** until you explicitly save — and the constant
"Guardada" toasts are only auto-saving the data-source edits, not the report. Close the tab and the
whole canvas is gone. (That is exactly what happened; hence this recipe.)

**Do this instead:** go to <https://lookerstudio.google.com> → **Crear → Informe** (Create → Report).
Then immediately confirm it persisted:

- the URL becomes `…/reporting/<long-id>/page/<id>/edit` (a real report id), and
- the top-right shows **"Compartir" and "Ver"** buttons (a *new/unsaved* report shows "Guardar y
  compartir" instead).

If you see those, the report is saved and every later edit auto-saves. Rename it now (top-left title)
to **"Parabolic Reversal — Setup Funnel (in-sample)"**.

## Step 1 — connect both marts

Add data → **BigQuery** → project `quant-trading-502717` → dataset `equities_marts` → add
`fct_setup_funnel`. Then Add data again and add `fct_signal_candidates`. (The Linking API URL that
pre-connects both *usually* errors on the `CREATE` step — the manual path above is the reliable one.)
Owner credentials is fine.

## Step 2 — the one calculated field: Win rate %

On the `fct_setup_funnel` source: Add a field → name it **`Win rate %`**, formula exactly:

```
100 * SUM(CASE WHEN is_winner THEN 1 ELSE 0 END) / SUM(CASE WHEN is_traded THEN 1 ELSE 0 END)
```

`is_winner`/`is_traded` are booleans; the `CASE … THEN 1 ELSE 0` casts them so `SUM` works. The `×100`
makes it read as a percentage number (78,9) — simpler and more robust than fighting the field-type =
Percent dropdown, which renders below the fold on a short screen. It should evaluate to **78,9**
(= 258/327). This field feeds both the KPI scorecard and the by-`days_up` chart.

## Step 3 — the caveat text box (do it first so it's never forgotten)

Insert → Texto, full width across the top. Paste verbatim:

> Parabolic Reversal — Setup Funnel (IN-SAMPLE). Walk-forward validation pending. Win rate 258/327
> executed trades; 582 of 909 candidates never triggered. Signals reimplement the entry rules on
> 1-min bars — they do NOT reproduce or validate the tick backtest (57.5% overlap).

## Step 4 — six elements (with the exact values they showed)

Grain matters: elements 1–4 read **fct_setup_funnel**; element 6 reads **fct_signal_candidates**. Set
each chart's data source explicitly (the panel defaults to whichever source was used last).

| # | element | type | source | dimension → metric | shows |
|---|---|---|---|---|---|
| 1 | **Win rate** | Scorecard | fct_setup_funnel | metric = `Win rate %` | **78,9** |
| 2 | **Candidate setups** | Scorecard | fct_setup_funnel | metric = `Record Count` | **909** |
| 3 | **Net PnL (in-sample)** | Scorecard | fct_setup_funnel | metric = `SUM(pnl)` | **580.381,32** |
| 4 | **The funnel** | Column/Bar | fct_setup_funnel | `funnel_stage` → `Record Count` | never_triggered **582**, won **258**, lost **69** |
| 5 | **Win rate by run-up** | Column/Bar | fct_setup_funnel | `days_up` → `Win rate %` | rises ~78 (1 day) → ~100 (4–5 days) |
| 6 | **Signals over time** | Time series | fct_signal_candidates | `session_date` → `Record Count` | activity spikes across 2020–2023 |

Layout that worked: caveat banner on top; the three scorecards in a row beneath it (select all three →
**Organizar → Alinear** to line them up); the funnel and the by-`days_up` bar side by side; the time
series full-width along the bottom.

Element 5 is the finding worth narrating in an interview: **the fade wins more often the larger the
prior run-up.** Element 6 is the "monitoring" view — it also visually makes the reimplementation point
(it fires on far more days than the 909 tick-backtest setups; see the README finding).

## Step 5 — publish view-only, then link it

Top-right **Compartir** → acceso general → **Cualquier usuario con el enlace → Lector** (Anyone with
the link → Viewer). Copy the link, paste it into `README.md` (the status line + the deliverables
section), and commit. Publishing exposes the marts' *aggregates* (not raw bars); given it's your own
in-sample research with the caveat attached, view-only is normal for a CV piece — but the click is
yours.

## What to be ready to say about it

The dashboard presents the marts, nothing more — the logic is in dbt. "Where does the win rate come
from?" → `fct_setup_funnel`, computed in SQL and tested; Looker only counts. Logic in the warehouse,
presentation in BI — that separation is the point.
