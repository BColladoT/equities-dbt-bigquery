{{ config(materialized='view') }}

-- The 909 candidate setups the V5 scanner found, typed and renamed. One row per setup.
--
-- Casts use dbt's built-in cross-database type macros ({{ '{{ dbt.type_float() }}' }} etc.) rather than a
-- literal `float64`, because this project builds on two engines: BigQuery spells it FLOAT64 and
-- DuckDB spells it DOUBLE. The macro is dbt's, not ours -- it resolves per adapter at compile
-- time. Same reason `int64` is not hardcoded below.

with source as (

    select * from {{ ref('setups') }}

),

renamed as (

    select
        symbol,
        date                                        as setup_date,

        cast(open   as {{ dbt.type_float() }})      as open_price,
        cast(high   as {{ dbt.type_float() }})      as high_price,
        cast(low    as {{ dbt.type_float() }})      as low_price,
        cast(close  as {{ dbt.type_float() }})      as close_price,
        cast(volume as {{ dbt.type_bigint() }})     as setup_volume,

        -- The CSV carries percent (66.5); every other ratio in this project is a fraction
        -- (close/vwap = 1.15, day_gain = 0.50). Converted once, here, so downstream never has to
        -- remember which unit this particular column happens to use.
        cast(gain_percent as {{ dbt.type_float() }}) / 100.0 as gain_pct,

        cast(days_up    as {{ dbt.type_int() }})    as days_up,
        cast(prior_gain as {{ dbt.type_float() }})  as prior_gain

    from source

)

select * from renamed
