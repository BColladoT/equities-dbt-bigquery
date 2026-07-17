{% if target.type == 'bigquery' %}
{{ config(
    materialized='table',
    partition_by={'field': 'session_date', 'data_type': 'date'},
    cluster_by=['symbol']
) }}
{% else %}
{{ config(materialized='table') }}
{% endif %}

-- V5's documented entry rules, REIMPLEMENTED IN SQL over Alpaca 1-minute bars.
--
-- ===========================================================================================
-- THIS IS NOT A REPRODUCTION OF THE BACKTEST, AND IT MUST NOT BE READ AS ONE.
--
-- The V5 engine (v5_strict.py:65-69) runs on TICK data aggregated to 60-second bars and anchors
-- VWAP at the first bar of its tick feed. This runs on Alpaca 1-minute bars anchored at 09:30
-- ET. Different input data, different anchor, different engine. The counts WILL differ, by
-- construction. The two are NOT a validation of each other -- neither one confirms the other is
-- right, and a match would be luck rather than evidence.
--
-- The trap, named so it can be refused: if this count disagrees with the tick backtest and we
-- "fix" it by nudging 1.15 / 0.70 / 0.93, we have fitted to the answer and the model means
-- nothing. Thresholds are frozen at the v5_strict.py:47-50 values. A divergence is a finding to
-- explain, never a number to tune. If the gap looks embarrassing, it gets published anyway.
-- See docs/superpowers/specs/ 5.1 and the README's "Finding" section.
-- ===========================================================================================
--
-- WHY THIS MART EXISTS AT ALL: without it, nothing downstream reads the bar pipeline, and the
-- whole DAG would be a live lineage graph over 1,818 rows of CSV while 20.4M bars sat unused.
-- That is the "folder of SQL scripts" dbt is supposed to beat. This mart is what makes dbt
-- COMPUTE the strategy rather than just report a CSV of results Python already produced.

with eligible as (

    select *
    from {{ ref('int_bars_exhaustion') }}
    -- Quality gates: ALL must pass. Frozen, with source lines.
    where bar_time_et between time '09:45:00' and time '14:00:00'  -- v5_strict.py:138 (inclusive)
      and day_gain     >= 0.50                                     -- v5_strict.py:143
      and close_price  >= session_vwap                             -- v5_strict.py:146 (momentum intact)
      and criteria_met >= 2                                        -- v5_strict.py:160 (2-of-3)

),

ranked as (

    select
        *,
        -- V5 takes the highest-extension setup and holds max 1 position/day
        -- (v5_strict.py:161-162, 177). We keep EVERY qualifying bar and FLAG the best one
        -- rather than filtering to rank 1: a mart called "candidates" that silently drops
        -- candidates would be lying about its own name. The flag lets a consumer reproduce V5's
        -- one-per-day selection with a WHERE clause, without this model destroying the
        -- information first.
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
