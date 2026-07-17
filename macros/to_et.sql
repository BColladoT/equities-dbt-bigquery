{#
    Convert a UTC timestamp column to a naive New York wall-clock timestamp.

    WHY THIS MACRO EXISTS: this project has two targets -- DuckDB (dev, runs today) and BigQuery
    (prod, configured but not yet run). Timezone conversion is the one piece of syntax the two
    engines genuinely disagree on, and every single source timestamp here is UTC while every
    threshold in the strategy is ET. So the conversion happens in exactly one place.

    NEVER a hardcoded offset. New York is UTC-5 in winter and UTC-4 in summer; hardcoding either
    silently shifts every bar by an hour for roughly half the year, which would move bars in and
    out of the 09:45-14:00 ET entry window and quietly change the signal count. Both engines are
    asked for 'America/New_York' by name so their own DST tables do the work.

    Both expressions return a NAIVE timestamp (no zone attached) holding ET wall-clock time,
    which is what the session-date and session-phase logic downstream expects.
      BigQuery: datetime(ts, 'America/New_York')     TIMESTAMP -> DATETIME
      DuckDB:   (ts AT TIME ZONE 'America/New_York') TIMESTAMPTZ -> TIMESTAMP
#}

{% macro to_et(ts_column) %}
    {%- if target.type == 'bigquery' -%}
        datetime({{ ts_column }}, 'America/New_York')
    {%- else -%}
        ({{ ts_column }} AT TIME ZONE 'America/New_York')
    {%- endif -%}
{% endmacro %}
