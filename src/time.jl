# ============================================================================
# Timer — simulation clock with weekday / weekend step schedules
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

mutable struct Timer
    initial_day::DateTime
    total_days::Int
    date::DateTime
    previous_date::DateTime
    final_date::DateTime
    shift::Int                              # current step within day (0-based)
    now::Float64                            # elapsed time in days
    weekday_step_duration::Vector{Float64}  # hours per step on weekdays
    weekend_step_duration::Vector{Float64}  # hours per step on weekends
    weekday_activities::Vector{Vector{String}}
    weekend_activities::Vector{Vector{String}}
    delta_time::Dates.Millisecond
    duration::Float64                       # current step length in days
end

"""
    timer_from_file(config_path::String)

Build a `Timer` from the `time` section of a YAML config.
"""
function timer_from_file(config_path::String)
    cfg = YAML.load_file(config_path)
    time_cfg = get(cfg, "time", cfg)

    initial_str = get(time_cfg, "initial_day", "2020-03-01")
    initial_day = DateTime(initial_str, dateformat"yyyy-mm-dd")
    total_days  = Int(get(time_cfg, "total_days", 100))
    final_date  = initial_day + Dates.Day(total_days)

    weekday_cfg = get(time_cfg, "step_duration", Dict("weekday" => [8.0, 8.0, 8.0]))
    weekend_cfg = get(time_cfg, "step_duration", Dict("weekend" => [12.0, 12.0]))

    weekday_step = Float64.(get(weekday_cfg, "weekday", [8.0, 8.0, 8.0]))
    weekend_step = Float64.(get(weekend_cfg, "weekend", [12.0, 12.0]))

    weekday_act_cfg = get(time_cfg, "step_activities", Dict())
    weekend_act_cfg = get(time_cfg, "step_activities", Dict())

    weekday_activities = _parse_activities(get(weekday_act_cfg, "weekday", nothing), length(weekday_step))
    weekend_activities = _parse_activities(get(weekend_act_cfg, "weekend", nothing), length(weekend_step))

    return Timer(
        initial_day,
        total_days,
        initial_day,        # date
        initial_day,        # previous_date
        final_date,
        0,                  # shift
        0.0,                # now
        weekday_step,
        weekend_step,
        weekday_activities,
        weekend_activities,
        Dates.Millisecond(0),
        0.0,                # duration
    )
end

function _parse_activities(raw, n_steps::Int)
    if raw === nothing || isempty(raw)
        return [String[] for _ in 1:n_steps]
    end
    result = Vector{Vector{String}}()
    for entry in raw
        if isa(entry, AbstractVector)
            push!(result, String.(entry))
        elseif isa(entry, AbstractString)
            push!(result, [String(entry)])
        else
            push!(result, String[])
        end
    end
    # Pad or truncate to n_steps
    while length(result) < n_steps
        push!(result, String[])
    end
    return result[1:n_steps]
end

"""
    is_weekend(t::Timer)

True when the current date falls on Saturday or Sunday.
"""
is_weekend(t::Timer) = Dates.dayofweek(t.date) >= 6

"""
    day_type(t::Timer)

Return `"weekend"` or `"weekday"`.
"""
day_type(t::Timer) = is_weekend(t) ? "weekend" : "weekday"

"""
    activities(t::Timer)

Return the activity list for the current step.
"""
function activities(t::Timer)
    if is_weekend(t)
        schedule = t.weekend_activities
    else
        schedule = t.weekday_activities
    end
    idx = t.shift + 1  # 1-based
    if idx < 1 || idx > length(schedule)
        return String[]
    end
    return schedule[idx]
end

"""
    advance!(t::Timer)

Move the timer forward by one step.  Returns `true` while the simulation has
not exceeded `final_date`; returns `false` to signal completion.
"""
function advance!(t::Timer)
    t.previous_date = t.date

    step_durations = is_weekend(t) ? t.weekend_step_duration : t.weekday_step_duration
    n_steps = length(step_durations)
    idx = t.shift + 1  # 1-based
    if idx < 1 || idx > n_steps
        idx = 1
    end

    duration_hours = step_durations[idx]
    t.delta_time = Dates.Millisecond(round(Int, duration_hours * 3_600_000))
    t.date += t.delta_time
    t.duration = duration_hours / 24.0
    t.now = Dates.value(t.date - t.initial_day) / (24.0 * 3_600_000)

    t.shift += 1
    if t.shift >= n_steps
        t.shift = 0
    end

    return t.date <= t.final_date
end

# Iteration protocol: enables `for step in timer ... end`
function Base.iterate(t::Timer)
    if t.date > t.final_date
        return nothing
    end
    ok = advance!(t)
    return ok ? (t, nothing) : nothing
end

function Base.iterate(t::Timer, ::Nothing)
    if t.date > t.final_date
        return nothing
    end
    ok = advance!(t)
    return ok ? (t, nothing) : nothing
end

Base.IteratorSize(::Type{Timer}) = Base.SizeUnknown()
Base.eltype(::Type{Timer}) = Timer

function Base.show(io::IO, t::Timer)
    print(io, "Timer(date=$(t.date), day=$(round(t.now, digits=2)), shift=$(t.shift))")
end
