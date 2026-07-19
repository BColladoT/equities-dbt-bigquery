{{ config(materialized='view') }}

-- Outcome per candidate setup, as produced by the tick-based V5 engine. One row per setup.
--
-- This is a REPORT of a backtest this project did not run. Nothing here is recomputed from bars;
-- fct_signal_candidates does that separately and deliberately does not reconcile with it.
-- See the README (Finding).
--
-- `win`/`loss` arrive as 0/1 integers. They become real booleans here, because `is_win` reads as
-- a fact and `win = 1` reads as a puzzle.

with source as (

    select * from {{ ref('backtest_results') }}

),

renamed as (

    select
        symbol,
        date                                       as setup_date,

        -- Percent -> fraction, matching stg_backtest__setups.gain_pct.
        cast(gain_pct as {{ dbt.type_float() }}) / 100.0 as gain_pct,

        cast(days_up as {{ dbt.type_int() }})      as days_up,
        cast(volume  as {{ dbt.type_bigint() }})   as setup_volume,
        cast(trades  as {{ dbt.type_int() }})      as trades,
        cast(pnl     as {{ dbt.type_float() }})    as pnl,

        cast(win  as {{ dbt.type_int() }}) = 1     as is_win,
        cast(loss as {{ dbt.type_int() }}) = 1     as is_loss

    from source

)

select * from renamed
