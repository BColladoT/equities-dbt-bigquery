{{ config(materialized='view') }}

-- V5's 2-of-3 entry criteria, evaluated per bar. Carries the VWAP fields through so downstream
-- reads one model, not two.
--
-- THRESHOLDS ARE FROZEN at v5_strict.py:47-50. They are NOT tuning knobs. If our signal count
-- disagrees with the tick backtest, that is a finding to explain -- never a number to adjust.
-- Fitting 1.15 / 0.70 / 0.93 to make the counts line up would mean fitting to the answer, and
-- the model would then mean precisely nothing. See docs/superpowers/specs/ 5.1.
--
-- A view, not a table: it adds a single window function to a model that is already materialised,
-- and nothing here is expensive enough to be worth paying storage for.

with base as (

    select * from {{ ref('int_bars_session_vwap') }}

),

with_vol_peak as (

    select
        *,
        -- max volume over the last 10 bars INCLUDING the current one -- matches
        -- v5_strict.py:124-127, where volume_history is appended-then-capped at 10 before
        -- vol_peak is taken. "10 bars" means 10 BARS, not 10 minutes: bars are sparse, so this
        -- window can span hours of wall-clock time. That is deliberate and matches V5, which
        -- also counts bars rather than minutes.
        max(volume) over (
            partition by symbol, session_date
            order by bar_ts_utc
            rows between 9 preceding and current row
        ) as vol_peak_10
    from base

),

ratios as (

    -- Each ratio computed ONCE here, then compared in the next CTE. Standard SQL cannot
    -- reference a select alias from within the same select list, so without this step every
    -- division would have to be written twice -- once for the output column and once inside its
    -- own threshold comparison -- and the two could silently drift apart.
    select
        *,
        volume      / nullif(vol_peak_10, 0) as volume_ratio,      -- v5_strict.py:151
        close_price / nullif(day_high, 0)    as proximity_to_high  -- v5_strict.py:152
    from with_vol_peak

),

criteria as (

    select
        *,
        vwap_extension_ratio >= 1.15 as meets_vwap_extension,     -- v5_strict.py:47, :155
        volume_ratio         <= 0.70 as meets_volume_exhaustion,  -- v5_strict.py:48, :156
        proximity_to_high    >= 0.93 as meets_proximity           -- v5_strict.py:49, :157
    from ratios

)

select
    *,
    -- v5_strict.py:154-158. `case when x then 1 else 0 end` rather than casting the boolean to
    -- an int: it is portable across both targets, and it makes NULL count as "criterion not
    -- met" rather than poisoning the whole sum to NULL.
    case when meets_vwap_extension    then 1 else 0 end
  + case when meets_volume_exhaustion then 1 else 0 end
  + case when meets_proximity         then 1 else 0 end as criteria_met
from criteria
