{{ config(materialized='view') }}

-- The funnel, made explicit: candidate -> traded -> won.
--
-- 909 candidates, 327 traded, 258 won. The 78.9% headline is 258/327 -- win rate conventionally
-- uses EXECUTED trades, and that is correctly computed. But 582 of the 909 candidates never
-- triggered an entry at all, and the denominator is the first thing a competent interviewer asks
-- for. So the stages are surfaced as columns rather than collapsed into one number.
-- IN-SAMPLE; walk-forward out-of-sample validation pending.
--
-- This model reads the seed CSVs only. It does NOT touch the bar pipeline, which is why it
-- returns 909/327/258 on every target -- the 10-symbol dev sample subsets the bars, never the
-- seeds. Contrast fct_signal_candidates, which recomputes the strategy from bars and is not
-- expected to agree with these numbers at all.

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

    -- Funnel stages. LEFT JOIN above means a setup with no result row still counts as a
    -- candidate; coalesce makes the absence read as "not traded" rather than NULL.
    true                                       as is_candidate,
    coalesce(r.trades > 0, false)              as is_traded,
    coalesce(r.trades > 0 and r.is_win, false) as is_winner

from setups s
left join results r
    on  s.symbol     = r.symbol
    and s.setup_date = r.setup_date
