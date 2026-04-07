"""
    SymptomTag

A tag for the symptoms exhibited by a person.
Higher numbers are more severe.
Values 0–4 (asymptomatic … intensive_care) correspond to health-index slots.

Mirrors the Python IntEnum:
    recovered = -3, healthy = -2, exposed = -1, asymptomatic = 0,
    mild = 1, severe = 2, hospitalised = 3, intensive_care = 4,
    dead_home = 5, dead_hospital = 6, dead_icu = 7

Julia `@enum` values must be non-negative, so we store offset values
(actual + 3) and provide `symptom_value` / `symptom_from_value` for
the true integer mapping.
"""

const _SYMPTOM_OFFSET = 3

@enum SymptomTag begin
    recovered       = 0   # actual -3
    healthy         = 1   # actual -2
    exposed         = 2   # actual -1
    asymptomatic    = 3   # actual  0
    mild            = 4   # actual  1
    severe          = 5   # actual  2
    hospitalised    = 6   # actual  3
    intensive_care  = 7   # actual  4
    dead_home       = 8   # actual  5
    dead_hospital   = 9   # actual  6
    dead_icu        = 10  # actual  7
end

"""Return the true integer value (-3 … 7) for a `SymptomTag`."""
symptom_value(tag::SymptomTag) = Int(tag) - _SYMPTOM_OFFSET

"""Look up a `SymptomTag` from its true integer value (-3 … 7)."""
function symptom_from_value(v::Integer)
    idx = v + _SYMPTOM_OFFSET
    return SymptomTag(idx)
end

"""Look up a `SymptomTag` from its name string (e.g. `"mild"`)."""
function symptom_from_string(s::AbstractString)
    sym = Symbol(s)
    for tag in instances(SymptomTag)
        if Symbol(tag) == sym
            return tag
        end
    end
    throw(ArgumentError("\"$s\" is not the name of a SymptomTag"))
end

# ── Predicates ───────────────────────────────────────────────────────────

"""True when the tag represents a dead outcome."""
is_dead(tag::SymptomTag) = tag in (dead_home, dead_hospital, dead_icu)

"""True when the person has been infected (exposed or worse, excluding recovered)."""
is_infected(tag::SymptomTag) = symptom_value(tag) >= symptom_value(exposed) && tag !== recovered

"""True when the person should be in hospital (hospitalised or ICU)."""
should_be_in_hospital(tag::SymptomTag) = tag in (hospitalised, intensive_care)
