{{ config(materialized='view') }}

-- One row per 1-minute bar, exactly as Alpaca sent it: cast, renamed, and given ET session
-- context.
--
-- NO FILTERING, BY DESIGN. The source was profiled clean on 2026-07-17 -- 0 malformed bars,
-- 0 nulls, 0 duplicate timestamps across all 20,391,519 rows. A `where` clause here would not
-- clean anything today; it would only hide garbage that arrives tomorrow. The tests are the
-- mechanism for that (tests/assert_no_malformed_bars.sql, unique on bar_key), not a WHERE.
-- A filter fixes rows silently. A test fails loudly. Loud is the requirement.

with source as (

    select * from {{ source('alpaca', 'bars_1min') }}

),

with_et as (

    -- The UTC -> ET conversion happens exactly ONCE, here, and everything else derives from it.
    -- Every source timestamp is UTC and every strategy threshold is ET, so this is the single
    -- highest-risk line in the project. One call site means one place to check, and the DST
    -- rules are the engine's problem, not ours. See macros/to_et.sql.
    select
        *,
        {{ to_et('timestamp') }} as bar_ts_et
    from source

),

with_et_parts as (

    select
        *,
        cast(bar_ts_et as date) as session_date,
        cast(bar_ts_et as time) as bar_time_et
    from with_et

),

renamed as (

    select
        -- Surrogate key over the natural key (symbol, timestamp). A single hashed column is
        -- testable with a one-line `unique` test and joinable with a single predicate; the
        -- two-column natural key needs a compound test and a two-column join everywhere.
        {{ dbt_utils.generate_surrogate_key(['symbol', 'timestamp']) }} as bar_key,

        symbol,
        timestamp    as bar_ts_utc,
        bar_ts_et,
        session_date,
        bar_time_et,

        open         as open_price,
        high         as high_price,
        low          as low_price,
        close        as close_price,
        volume,

        -- Alpaca's PER-BAR vwap: one minute's worth of trading. NOT session VWAP.
        -- Renamed rather than dropped, because staging's job is to report the source faithfully
        -- -- but renamed with `bar_` on the front so it can never be mistaken for the session
        -- VWAP computed in int_bars_session_vwap.
        vwap         as bar_vwap,

        -- KNOWN BOUNDARY, stated rather than buried: the `else` branch calls everything left
        -- over 'postmarket'. That is only correct while no bar lands between 00:00 and 04:00 ET,
        -- since such a bar would be filed as postmarket when it is really overnight. Verified
        -- true for this data (earliest observed bar is 08:00 ET; Alpaca's extended-hours feed
        -- starts at 04:00). If that ever changes, this branch is where it breaks.
        case
            when bar_time_et >= time '09:30:00' and bar_time_et < time '16:00:00' then 'regular'
            when bar_time_et >= time '04:00:00' and bar_time_et < time '09:30:00' then 'premarket'
            else 'postmarket'
        end          as session_phase

    from with_et_parts

)

select * from renamed
