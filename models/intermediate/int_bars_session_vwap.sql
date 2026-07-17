{% if target.type == 'bigquery' %}
{{ config(
    materialized='table',
    partition_by={'field': 'session_date', 'data_type': 'date'},
    cluster_by=['symbol']
) }}
{% else %}
{{ config(materialized='table') }}
{% endif %}

-- Session VWAP, anchored at 09:30 ET, cumulative through the regular session.
--
-- WHY INTERMEDIATE, NOT STAGING: row grain does not settle it -- it is one row per bar either
-- way. OWNERSHIP settles it. `bar_vwap` exists because Alpaca sends it. `session_vwap` exists
-- because our strategy invented a 09:30 anchor. If the vendor changes their feed we fix staging;
-- if we move the anchor to premarket we fix this file. Keeping them apart means a vendor change
-- and a strategy change never touch the same model.
--
-- WHY A TABLE WHEN STAGING IS A VIEW: this is a window function over every bar in the dataset
-- (20.4M rows on the BigQuery target). As a view, that window would recompute on EVERY
-- downstream query -- both marts, plus every dashboard refresh. As a table it computes once per
-- `dbt run`. This is the one materialisation decision in the project that is actually
-- load-bearing rather than convention.
--
-- WHY PARTITION ON session_date WHEN THE RAW TABLE PARTITIONS ON UTC DATE: the raw table is
-- loaded faithfully as the vendor sent it (ELT, not ETL) so it partitions on UTC. We query by
-- trading session, so the first materialised model re-partitions on ET session_date and pruning
-- lines up with our actual filters. Two partition keys is the point, not a contradiction.
-- (The partition/cluster config is BigQuery-only and guarded above; DuckDB has no equivalent
-- and needs none at 220k rows.)
--
-- ANCHORING: filtering to the regular session and framing UNBOUNDED PRECEDING -> CURRENT ROW
-- anchors on the FIRST BAR AT OR AFTER 09:30, not on a literal 09:30 bar. Micro-cap bars are
-- sparse -- a 09:30 bar frequently does not exist -- so anchoring on one would produce nulls.
--
-- FIDELITY NOTE: V5 (v5_strict.py:75-89) anchors at the first bar of its TICK feed with no 09:30
-- filter. We anchor at 09:30 by explicit choice -- better defined, and it matches the documented
-- intent. This is one reason fct_signal_candidates cannot reproduce the tick backtest. See
-- docs/superpowers/specs/ 5.1.
--
-- DIVISION: `a / nullif(b, 0)` rather than BigQuery's safe_divide(), which DuckDB does not have.
-- Same behaviour -- divide by zero yields null instead of raising -- in portable SQL.

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
        -- everything from the session's first bar up to and including this one
        w_running as (
            partition by symbol, session_date
            order by bar_ts_utc
            rows between unbounded preceding and current row
        ),
        -- the whole session, regardless of where we are in it
        w_session as (
            partition by symbol, session_date
            order by bar_ts_utc
            rows between unbounded preceding and unbounded following
        )

),

with_session_vwap as (

    select
        *,
        cum_tp_volume / nullif(cum_volume, 0) as session_vwap
    from cumulative

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

    session_vwap,

    -- close / vwap, matching v5_strict.py:150. Compared against the frozen 1.15 downstream.
    close_price / nullif(session_vwap, 0)      as vwap_extension_ratio,

    -- (day_high - day_open) / day_open, matching v5_strict.py:142
    (day_high - day_open) / nullif(day_open, 0) as day_gain

from with_session_vwap
