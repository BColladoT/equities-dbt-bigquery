{{ config(materialized='table') }}

-- THE HEADLINE STORY: 909 candidates -> 327 traded -> 258 won (78.9% on executed trades).
--
-- The funnel IS the point. A dashboard that reports "79% win rate" and stops is hiding that 582
-- of 909 candidate setups never triggered an entry at all. That number is not embarrassing --
-- it is how the strategy works, it only fires when conditions are met -- but it is the first
-- thing a competent interviewer asks for, and volunteering it reads as rigour while being caught
-- without it reads as the opposite. So the stages are columns here, not a footnote.
--
-- IN-SAMPLE. Walk-forward out-of-sample validation pending. These are not live, audited, or
-- validated results.
--
-- LEFT JOIN, NOT INNER -- and this is the load-bearing line in the model. A setup with no
-- matching session features must STILL appear in the funnel. An inner join would silently shrink
-- the denominator from 909 to whatever happened to match, quietly inflating the win rate: the
-- exact dishonesty this mart exists to prevent. On the DuckDB dev target that matters
-- immediately -- the committed sample carries bars for only 10 symbols, so most setups have no
-- session features and `has_bar_data` is false for them. The funnel counts must stay 909/327/258
-- regardless. If they move, the join is wrong.

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

    -- One mutually-exclusive stage per setup, so a chart can group by it without needing to know
    -- the boolean precedence rules. Order matters: a winner is also traded, so `won` is tested
    -- first.
    case
        when o.is_winner then 'won'
        when o.is_traded then 'lost'
        else 'never_triggered'
    end as funnel_stage,

    -- Session context from the bar pipeline. Null wherever bars are absent -- see has_bar_data.
    f.bar_count,
    f.session_volume,
    f.max_vwap_extension_ratio,
    f.max_day_gain,
    f.peak_extension_ts_et,
    f.bars_meeting_2of3,

    -- Explicit rather than inferred: lets a consumer filter to setups we can actually say
    -- something about, without mistaking "no bars loaded" for "nothing happened".
    f.symbol is not null as has_bar_data

from outcomes o
left join session_features f
    on  o.symbol     = f.symbol
    and o.setup_date = f.session_date
