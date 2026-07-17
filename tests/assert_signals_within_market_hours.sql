-- DOMAIN RULE: V5 only enters between 09:45 and 14:00 ET (v5_strict.py:138).
--
-- A signal outside that window means the UTC->ET conversion drifted. That is the single most
-- likely real bug in this project: EVERY source timestamp is UTC, every threshold is ET, and DST
-- moves the offset twice a year. Get it wrong and the models still build, the row counts still
-- look plausible, and every number is quietly an hour off for half the year.
--
-- SQL cannot infer this rule. `not_null` knows a timestamp exists; only someone who knows the
-- strategy can say a signal at 03:00 ET is impossible. That is what a singular test is for.
--
-- ------------------------------------------------------------------------------------------
-- KNOWN LIMIT OF THIS TEST -- stated rather than oversold:
--
-- This asserts the same bound that fct_signal_candidates already filters on, and it reads the
-- same bar_time_et column that filter uses. So if macros/to_et.sql were itself wrong, the filter
-- and this test would share the error and agree with each other. This is therefore a REGRESSION
-- GUARD on the filter (someone widens the WHERE clause, or a refactor drops it) -- it is NOT an
-- independent audit of the timezone conversion.
--
-- An earlier version tried to close that gap by cross-checking raw bar_ts_utc against the widest
-- possible ET offset (13:45-19:00 UTC). It was reverted: extracting a time-of-day from a
-- TIMESTAMP WITH TIME ZONE is unimplemented in DuckDB and session-timezone-dependent on engines
-- where it works at all, so the "independent" check would have been both non-portable and
-- non-deterministic -- a worse bug than the one it was catching, planted in the one target we
-- cannot currently run.
--
-- The conversion itself is instead defended by construction: exactly one call site
-- (stg_alpaca__bars_1min), one macro, no hardcoded offsets, both engines asked for
-- 'America/New_York' by name so their own DST tables do the work. Verifying that properly needs
-- a fixture with known DST-boundary timestamps and expected ET values -- worth doing, not done
-- yet. See README "What this project does not do".
-- ------------------------------------------------------------------------------------------

select
    bar_key,
    symbol,
    session_date,
    bar_ts_utc,
    bar_ts_et,
    bar_time_et
from {{ ref('fct_signal_candidates') }}
where bar_time_et < time '09:45:00'
   or bar_time_et > time '14:00:00'
