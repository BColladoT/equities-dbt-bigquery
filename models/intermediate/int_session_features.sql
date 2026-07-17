{{ config(materialized='table') }}

-- Bar grain -> session grain. This is the fork in the DAG: fct_signal_candidates keeps bar grain
-- (one row per firing signal), while fct_setup_funnel needs exactly one row per
-- (symbol, session_date) to join onto a setup without fanning it out.

with ranked_bars as (

    -- Rank each session's bars by how extended they were. Used only to pick the peak bar's
    -- timestamp below.
    --
    -- PORTABILITY: BigQuery would express "the timestamp of the most-extended bar" as
    -- array_agg(bar_ts_et order by vwap_extension_ratio desc limit 1)[offset(0)]. DuckDB has no
    -- offset(); a ranked window works identically on both engines. The bar_ts_utc tiebreak makes
    -- it deterministic -- without it, two bars at the same extension would make the result depend
    -- on scan order.
    select
        *,
        row_number() over (
            partition by symbol, session_date
            order by vwap_extension_ratio desc, bar_ts_utc asc
        ) as extension_rank
    from {{ ref('int_bars_exhaustion') }}

)

select
    symbol,
    session_date,

    count(*)                  as bar_count,
    sum(volume)               as session_volume,
    max(vwap_extension_ratio) as max_vwap_extension_ratio,
    max(day_gain)             as max_day_gain,
    max(day_high)             as day_high,
    min(day_open)             as day_open,
    min(bar_ts_et)            as first_bar_ts_et,
    max(bar_ts_et)            as last_bar_ts_et,

    -- Exactly one bar per session has extension_rank = 1, so min() over the CASE picks that one
    -- bar's timestamp and ignores the nulls from every other row. This is the portable
    -- equivalent of "argmax".
    min(case when extension_rank = 1 then bar_ts_et end) as peak_extension_ts_et,

    max(criteria_met)         as max_criteria_met,
    -- countif() is BigQuery-only (and DuckDB happens to have it too, but not every engine does).
    -- sum(case when ...) is plain ANSI SQL and says the same thing.
    sum(case when criteria_met >= 2 then 1 else 0 end) as bars_meeting_2of3

from ranked_bars
group by symbol, session_date
