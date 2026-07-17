-- DOMAIN RULE: a bar's low can never exceed its high, open and close must sit inside [low, high],
-- and volume can never be negative. These are physically impossible in a real market -- not
-- "unlikely", impossible. If this fires, Alpaca sent garbage or our load corrupted the data.
--
-- SQL cannot infer this rule. A `not_null` test knows a column has values; only a human who knows
-- what a candlestick IS can say that low > high is nonsense. That is what a singular test is for.
--
-- Verified 0 violations across all 20,391,519 rows on 2026-07-17. It is GREEN today, by design.
-- A test is a contract, not a discovery: it encodes what must remain true, and it fires when it
-- stops being true. This is a tripwire nobody has tripped, not a test that does nothing.

select
    bar_key,
    symbol,
    bar_ts_utc,
    open_price,
    high_price,
    low_price,
    close_price,
    volume
from {{ ref('stg_alpaca__bars_1min') }}
where low_price  > high_price
   or high_price < greatest(open_price, close_price)
   or low_price  > least(open_price, close_price)
   or volume     < 0
