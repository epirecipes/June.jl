# ============================================================================
# ImmunitySetter — population-level immunity initialisation
#
# Included inside `module June`; no sub-module wrapper.
# Assumes Immunity, Person, Population, YAML are available.
# ============================================================================

struct ImmunitySetter
    susceptibility_dict::Dict{Int, Dict{String, Float64}}   # infection_id → age_range → susceptibility
    multiplier_dict::Dict{Int, Dict{String, Float64}}       # infection_id → age_range → multiplier
    susceptibility_mode::Symbol                               # :average or :individual
end

"""
    immunity_setter_from_file(config_path::String)

Load an `ImmunitySetter` from a YAML config.

Expected YAML structure:
```yaml
susceptibility_mode: "average"
susceptibility:
  0:            # infection_id
    "0-17": 0.5
    "18-64": 0.8
    "65+": 0.9
multipliers:
  0:
    "0-17": 1.0
    "18-64": 1.2
    "65+": 1.5
```
"""
function immunity_setter_from_file(config_path::String)
    config = YAML.load_file(config_path)

    mode = Symbol(get(config, "susceptibility_mode", "average"))

    susc = Dict{Int, Dict{String, Float64}}()
    if haskey(config, "susceptibility")
        for (id_key, ranges) in config["susceptibility"]
            iid = isa(id_key, Integer) ? Int(id_key) : parse(Int, string(id_key))
            d = Dict{String, Float64}()
            for (rng, val) in ranges
                d[string(rng)] = Float64(val)
            end
            susc[iid] = d
        end
    end

    mult = Dict{Int, Dict{String, Float64}}()
    if haskey(config, "multipliers")
        for (id_key, ranges) in config["multipliers"]
            iid = isa(id_key, Integer) ? Int(id_key) : parse(Int, string(id_key))
            d = Dict{String, Float64}()
            for (rng, val) in ranges
                d[string(rng)] = Float64(val)
            end
            mult[iid] = d
        end
    end

    return ImmunitySetter(susc, mult, mode)
end

# ---------------------------------------------------------------------------
# Apply immunity to a world / population
# ---------------------------------------------------------------------------

"""
    set_immunity!(setter::ImmunitySetter, world)

Set initial immunity (susceptibilities and severity multipliers) for every
person in the world's population.
"""
function set_immunity!(setter::ImmunitySetter, world)
    world === nothing && return nothing
    pop = hasproperty(world, :people) ? world.people : nothing
    pop === nothing && return nothing
    set_susceptibilities!(setter, pop)
    set_multipliers!(setter, pop)
    return nothing
end

"""
    set_susceptibilities!(setter::ImmunitySetter, population::Population)

Assign per-person susceptibility values based on age ranges.
"""
function set_susceptibilities!(setter::ImmunitySetter, population::Population)
    for person in population
        if person.immunity === nothing
            person.immunity = Immunity()
        end
        for (infection_id, ranges) in setter.susceptibility_dict
            val = _lookup_age_value(ranges, person.age)
            if setter.susceptibility_mode == :individual
                val = rand() < val ? 1.0 : 0.0
            end
            person.immunity.susceptibility_dict[infection_id] = val
        end
    end
    return nothing
end

"""
    set_multipliers!(setter::ImmunitySetter, population::Population)

Assign per-person severity multiplier values based on age ranges.
"""
function set_multipliers!(setter::ImmunitySetter, population::Population)
    for person in population
        if person.immunity === nothing
            person.immunity = Immunity()
        end
        for (infection_id, ranges) in setter.multiplier_dict
            val = _lookup_age_value(ranges, person.age)
            person.immunity.effective_multiplier_dict[infection_id] = val
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

"""Look up a value from an age-range dictionary (e.g. `"0-17"`, `"18-64"`, `"65+"`)."""
function _lookup_age_value(ranges::Dict{String, Float64}, age::Int)
    for (rng, val) in ranges
        if _age_in_range(rng, age)
            return val
        end
    end
    return 1.0   # default: fully susceptible / no multiplier
end

"""Check whether `age` falls in the age-range string `rng` (e.g. `"0-17"`, `"65+"`)."""
function _age_in_range(rng::String, age::Int)
    if endswith(rng, "+")
        low = parse(Int, rng[1:end-1])
        return age >= low
    elseif occursin("-", rng)
        parts = split(rng, "-")
        low = parse(Int, parts[1])
        high = parse(Int, parts[2])
        return low <= age <= high
    else
        return age == parse(Int, rng)
    end
end
