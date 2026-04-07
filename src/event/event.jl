# ============================================================================
# Events — discrete events that modify simulation state
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

abstract type AbstractEvent end

"""
    is_active(e::AbstractEvent, date::DateTime)

True when `date` falls within the event's [start_time, end_time) window.
"""
function is_active(e::AbstractEvent, date::DateTime)
    start_ok = e.start_time === nothing || date >= e.start_time
    end_ok   = e.end_time === nothing   || date < e.end_time
    return start_ok && end_ok
end

# ---------------------------------------------------------------------------
# Concrete events
# ---------------------------------------------------------------------------

struct DomesticCare <: AbstractEvent
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
end

# ---------------------------------------------------------------------------
# Event collection
# ---------------------------------------------------------------------------

mutable struct Events
    events::Vector{AbstractEvent}
end

Events() = Events(AbstractEvent[])

"""
    events_from_file(config_path::String)

Load events from a YAML config file.
"""
function events_from_file(config_path::String)
    cfg = YAML.load_file(config_path)
    ev_cfg = get(cfg, "events", cfg)
    evts = Events()

    for e_cfg in get(ev_cfg, "event_list", [])
        etype = get(e_cfg, "type", "")
        st = _parse_event_datetime(get(e_cfg, "start_time", nothing))
        et = _parse_event_datetime(get(e_cfg, "end_time", nothing))

        if etype == "domestic_care"
            push!(evts.events, DomesticCare(st, et))
        end
    end
    return evts
end

function _parse_event_datetime(val)
    val === nothing && return nothing
    return DateTime(string(val), dateformat"yyyy-mm-dd")
end

"""
    init_events!(events::Events, world)

Initialise events that require world state (e.g. pre-assigning carers).
"""
function init_events!(events::Events, world)
    for evt in events.events
        if evt isa DomesticCare
            _init_domestic_care!(evt, world)
        end
    end
end

function _init_domestic_care!(evt::DomesticCare, world)
    # Placeholder: assign carers based on household structure
end

"""
    apply_events!(events::Events; date, world=nothing, activities=nothing,
                  day_type="weekday", simulator=nothing)

Apply all active events for the current time-step.
"""
function apply_events!(events::Events;
                       date::DateTime,
                       world=nothing,
                       activities=nothing,
                       day_type::String="weekday",
                       simulator=nothing)
    for evt in events.events
        !is_active(evt, date) && continue

        if evt isa DomesticCare
            _apply_domestic_care!(evt; world=world, activities=activities,
                                 day_type=day_type)
        end
    end
end

function _apply_domestic_care!(evt::DomesticCare;
                               world=nothing, activities=nothing,
                               day_type::String="weekday")
    # Placeholder: move carers to households requiring care
end

function Base.show(io::IO, evts::Events)
    print(io, "Events(n=$(length(evts.events)))")
end
