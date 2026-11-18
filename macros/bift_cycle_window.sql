{% macro _bift_parse_int(val, default_val=none) -%}
    {%- if val is none -%}
        {{ return(default_val) }}
    {%- endif -%}
    {%- set s = (val | string) | trim -%}
    {%- if s == '' or (s | lower) == 'none' or (s | lower) == 'null' -%}
        {{ return(default_val) }}
    {%- endif -%}
    {{ return(s | int) }}
{%- endmacro %}


{% macro bift_resolve_cycle_window(ns, relation_schema=none, relation_name=none, default_lookback_weeks=2) %}
    {%- set v_all_periods = var('all_periods', false) -%}
    {%- set v_tahun = _bift_parse_int(var('tahun', none)) -%}
    {%- set v_periode = _bift_parse_int(var('periode', none)) -%}
    {%- set v_periode_end = _bift_parse_int(var('periode_end', none), v_periode) -%}
    {%- set v_week = _bift_parse_int(var('week', none)) -%}
    {%- set v_week_start = _bift_parse_int(var('week_start', none), v_week) -%}
    {%- set v_week_end = _bift_parse_int(var('week_end', none), v_week_start) -%}
    {%- set v_lookback_days = _bift_parse_int(var('lookback_days', none)) -%}
    {%- set v_lookback_weeks = _bift_parse_int(var('lookback_weeks', none), default_lookback_weeks) -%}

    {%- set ns.filter_periods = true -%}
    {%- set ns.period_pairs = [] -%}
    {%- set ns.week_pairs = [] -%}
    {%- set ns.ypw_triples = [] -%}
    {%- set ns.tp_list = [] -%}
    {%- set ns.start_tahun = 2026 -%}
    {%- set ns.start_periode = 1 -%}
    {%- set ns.end_tahun = 2026 -%}
    {%- set ns.end_periode = 1 -%}

    {%- if v_all_periods -%}
        {%- set ns.filter_periods = false -%}
    {%- elif not execute -%}
        {%- set ns.period_pairs = [(2026, 1)] -%}
        {%- set ns.week_pairs = [(2026, 1)] -%}
        {%- set ns.ypw_triples = [(2026, 1, 1)] -%}
        {%- set ns.tp_list = [2601] -%}
    {%- elif v_periode is not none or v_week_start is not none -%}
        {%- if v_tahun is none -%}
            {%- set yr_res = run_query("SELECT COALESCE(MAX(year::int), EXTRACT(YEAR FROM CURRENT_DATE)::int) FROM spx.m_cycle3 WHERE cdate::date <= CURRENT_DATE") -%}
            {%- set y = (yr_res.columns[0].values()[0] | int) if (yr_res and (yr_res.rows | length) > 0) else 2026 -%}
        {%- else -%}
            {%- set y = v_tahun -%}
        {%- endif -%}

        {%- set cycle_sql -%}
            SELECT DISTINCT year::int AS tahun, period::int AS periode, week::int AS week_no
            FROM spx.m_cycle3
            WHERE year::int = {{ y }}
              {%- if v_periode is not none %}
              AND period::int BETWEEN {{ v_periode }} AND {{ v_periode_end }}
              {%- endif %}
              {%- if v_week_start is not none %}
              AND week::int BETWEEN {{ v_week_start }} AND {{ v_week_end }}
              {%- endif %}
            ORDER BY 1, 2, 3
        {%- endset -%}
        {%- set cycle_res = run_query(cycle_sql) -%}
        {%- if cycle_res and (cycle_res.rows | length) > 0 -%}
            {%- for row in cycle_res.rows -%}
                {%- set r_y = row[0] | int -%}
                {%- set r_p = row[1] | int -%}
                {%- set r_w = row[2] | int -%}
                {%- if (r_y, r_p) not in ns.period_pairs -%}
                    {%- set ns.period_pairs = ns.period_pairs + [(r_y, r_p)] -%}
                    {%- set ns.tp_list = ns.tp_list + [((r_y % 100) * 100 + r_p)] -%}
                {%- endif -%}
                {%- if (r_y, r_w) not in ns.week_pairs -%}
                    {%- set ns.week_pairs = ns.week_pairs + [(r_y, r_w)] -%}
                {%- endif -%}
                {%- if (r_y, r_p, r_w) not in ns.ypw_triples -%}
                    {%- set ns.ypw_triples = ns.ypw_triples + [(r_y, r_p, r_w)] -%}
                {%- endif -%}
            {%- endfor -%}
        {%- elif v_periode is not none and v_week_start is not none -%}
            {%- for p in range(v_periode, v_periode_end + 1) -%}
                {%- set ns.period_pairs = ns.period_pairs + [(y, p)] -%}
                {%- set ns.tp_list = ns.tp_list + [((y % 100) * 100 + p)] -%}
                {%- for w in range(v_week_start, v_week_end + 1) -%}
                    {%- if (y, w) not in ns.week_pairs -%}
                        {%- set ns.week_pairs = ns.week_pairs + [(y, w)] -%}
                    {%- endif -%}
                    {%- set ns.ypw_triples = ns.ypw_triples + [(y, p, w)] -%}
                {%- endfor -%}
            {%- endfor -%}
        {%- elif v_periode is not none -%}
            {%- for p in range(v_periode, v_periode_end + 1) -%}
                {%- set ns.period_pairs = ns.period_pairs + [(y, p)] -%}
                {%- set ns.tp_list = ns.tp_list + [((y % 100) * 100 + p)] -%}
            {%- endfor -%}
        {%- else -%}
            {{ exceptions.raise_compiler_error("No rows in spx.m_cycle3 matching tahun=" ~ y ~ ", periode=" ~ v_periode ~ ".." ~ v_periode_end ~ ", week=" ~ v_week_start ~ ".." ~ v_week_end) }}
        {%- endif -%}
    {%- else -%}
        {%- set can_filter = true -%}
        {%- if relation_schema is not none and relation_name is not none -%}
            {%- set rel = adapter.get_relation(database=target.dbname, schema=relation_schema, identifier=relation_name) -%}
            {%- if rel is none -%}
                {%- set can_filter = false -%}
            {%- else -%}
                {%- set has_data_res = run_query("SELECT EXISTS (SELECT 1 FROM " ~ relation_schema ~ "." ~ relation_name ~ " LIMIT 1)") -%}
                {%- set can_filter = has_data_res.columns[0].values()[0] if (has_data_res and (has_data_res.rows | length) > 0) else false -%}
            {%- endif -%}
        {%- endif -%}

        {%- if not can_filter -%}
            {%- set ns.filter_periods = false -%}
        {%- else -%}
            {%- if v_lookback_days is not none -%}
                {%- set cycle_sql -%}
                    SELECT DISTINCT year::int AS tahun, period::int AS periode, week::int AS week_no
                    FROM spx.m_cycle3
                    WHERE cdate::date BETWEEN (CURRENT_DATE - INTERVAL '{{ v_lookback_days }} days')::date AND CURRENT_DATE
                    ORDER BY 1, 2, 3
                {%- endset -%}
            {%- else -%}
                {%- set n_weeks = [v_lookback_weeks, 1] | max -%}
                {%- set cycle_sql -%}
                    WITH target_weeks AS (
                        SELECT DISTINCT year::int AS tahun, week::int AS week_no
                        FROM spx.m_cycle3
                        WHERE cdate::date <= CURRENT_DATE
                        ORDER BY 1 DESC, 2 DESC
                        LIMIT {{ n_weeks }}
                    )
                    SELECT DISTINCT c.year::int AS tahun, c.period::int AS periode, c.week::int AS week_no
                    FROM spx.m_cycle3 c
                    INNER JOIN target_weeks tw
                        ON c.year::int = tw.tahun
                       AND c.week::int = tw.week_no
                    ORDER BY 1, 2, 3
                {%- endset -%}
            {%- endif -%}
            {%- set cycle_res = run_query(cycle_sql) -%}
            {%- if cycle_res and (cycle_res.rows | length) > 0 -%}
                {%- for row in cycle_res.rows -%}
                    {%- set r_y = row[0] | int -%}
                    {%- set r_p = row[1] | int -%}
                    {%- set r_w = row[2] | int -%}
                    {%- if (r_y, r_p) not in ns.period_pairs -%}
                        {%- set ns.period_pairs = ns.period_pairs + [(r_y, r_p)] -%}
                        {%- set ns.tp_list = ns.tp_list + [((r_y % 100) * 100 + r_p)] -%}
                    {%- endif -%}
                    {%- if (r_y, r_w) not in ns.week_pairs -%}
                        {%- set ns.week_pairs = ns.week_pairs + [(r_y, r_w)] -%}
                    {%- endif -%}
                    {%- if (r_y, r_p, r_w) not in ns.ypw_triples -%}
                        {%- set ns.ypw_triples = ns.ypw_triples + [(r_y, r_p, r_w)] -%}
                    {%- endif -%}
                {%- endfor -%}
            {%- else -%}
                {%- set ns.filter_periods = false -%}
            {%- endif -%}
        {%- endif -%}
    {%- endif -%}

    {%- if (ns.period_pairs | length) > 0 -%}
        {%- set ns.start_tahun = ns.period_pairs[0][0] -%}
        {%- set ns.start_periode = ns.period_pairs[0][1] -%}
        {%- set ns.end_tahun = ns.period_pairs[-1][0] -%}
        {%- set ns.end_periode = ns.period_pairs[-1][1] -%}
    {%- endif -%}
{% endmacro %}


{% macro bift_delete_target_periods(mode='tp') %}
    {%- if execute and is_incremental() -%}
        {%- if var('all_periods', false) -%}
            TRUNCATE TABLE {{ this }};
        {%- else -%}
            {%- set has_data_res = run_query("SELECT EXISTS (SELECT 1 FROM " ~ this ~ " LIMIT 1)") -%}
            {%- set has_data = has_data_res.columns[0].values()[0] if (has_data_res and (has_data_res.rows | length) > 0) else false -%}
            {%- if has_data -%}
                {%- set ns = namespace() -%}
                {%- do bift_resolve_cycle_window(ns) -%}
                {%- if ns.filter_periods and mode == 'tp' and (ns.tp_list | length) > 0 -%}
                    DELETE FROM {{ this }}
                    WHERE tahun_periode IN ({{ ns.tp_list | join(', ') }});
                {%- elif ns.filter_periods and mode == 'yp' and (ns.period_pairs | length) > 0 -%}
                    DELETE FROM {{ this }}
                    WHERE (
                        {%- for pair in ns.period_pairs -%}
                        (tahun = {{ pair[0] }} AND periode = {{ pair[1] }}){% if not loop.last %} OR {% endif %}
                        {%- endfor -%}
                    );
                {%- endif -%}
            {%- endif -%}
        {%- endif -%}
    {%- endif -%}
{% endmacro %}


{% macro vfsales_delete_recent_window(lookback_days=10) %}
    {%- if execute and is_incremental() and not var('all_periods', false) -%}
        {%- set has_data_res = run_query("SELECT EXISTS (SELECT 1 FROM " ~ this ~ " LIMIT 1)") -%}
        {%- set has_data = has_data_res.columns[0].values()[0] if (has_data_res and (has_data_res.rows | length) > 0) else false -%}
        {%- if has_data -%}
            {%- set wk_res = run_query("SELECT DISTINCT year::int, week::int FROM spx.m_cycle3 WHERE cdate::date BETWEEN (CURRENT_DATE - INTERVAL '" ~ lookback_days ~ " days')::date AND CURRENT_DATE ORDER BY 1, 2") -%}
            {%- if wk_res and (wk_res.rows | length) > 0 -%}
                DELETE FROM {{ this }}
                WHERE inv_date >= CURRENT_DATE - INTERVAL '{{ lookback_days }} DAY'
                  AND ("year", week_no) IN (
                    {%- for row in wk_res.rows -%}
                    ({{ row[0] | int }}, {{ row[1] | int }}){% if not loop.last %}, {% endif %}
                    {%- endfor -%}
                  );
            {%- else -%}
                DELETE FROM {{ this }}
                WHERE inv_date >= CURRENT_DATE - INTERVAL '{{ lookback_days }} DAY';
            {%- endif -%}
        {%- endif -%}
    {%- endif -%}
{% endmacro %}
