# ============================================================================
# InfectionSelector — wires together health-index, trajectory, transmission
#
# Included inside `module June`; no sub-module wrapper.
# Assumes HealthIndexGenerator, TrajectoryMaker, Symptoms, Infection,
# transmission_from_config, Immunity helpers are already defined.
# ============================================================================

struct InfectionSelector
    infection_id::Int
    transmission_config::Dict
    trajectory_maker::TrajectoryMaker
    health_index_generator::HealthIndexGenerator
end

"""
    infection_selector_from_file(config_path::String; infection_id::Int=0)

Build an `InfectionSelector` from a YAML config.

Expected YAML keys:
- `transmission`: dict of transmission parameters
- `trajectories`: path to trajectories YAML file
- `health_index`: path to health-index YAML file
"""
function infection_selector_from_file(config_path::String; infection_id::Int=0)
    config = YAML.load_file(config_path)
    base_dir = dirname(config_path)

    transmission_config = config["transmission"]

    traj_path = joinpath(base_dir, config["trajectories"])
    trajectory_maker = trajectory_maker_from_file(traj_path)

    hi_path = joinpath(base_dir, config["health_index"])
    health_index_gen = health_index_from_file(hi_path)

    return InfectionSelector(infection_id, transmission_config,
                             trajectory_maker, health_index_gen)
end

"""
    get_immune_to(infection_id::Int)::Vector{Int}

Return the list of infection IDs that a person becomes immune to after being
infected with `infection_id`.  Default: immune to the same variant only.
"""
function get_immune_to(infection_id::Int)::Vector{Int}
    return [infection_id]
end

"""
    infect_person_at_time!(selector::InfectionSelector, person::Person, time::Float64)

Infect `person` at the given simulation `time` using the selector's
health-index, trajectory maker, and transmission config.
"""
function infect_person_at_time!(selector::InfectionSelector, person::Person, time::Float64)
    # 1. Determine health index for this person
    health_index = get_health_index(selector.health_index_generator, person, selector.infection_id)

    # 2. Create symptoms with random severity draw
    syms = Symptoms(health_index)

    # 3. Build trajectory from max_tag
    trajectory = make_trajectory(selector.trajectory_maker, syms.max_tag)
    set_trajectory!(syms, trajectory)

    # 4. Create transmission profile (shift may depend on symptoms onset)
    transmission = transmission_from_config(
        selector.transmission_config;
        time_to_symptoms_onset = syms.time_of_symptoms_onset,
    )

    # 5. Assign infection to person
    person.infection = Infection(transmission, syms, time; infection_id=selector.infection_id)

    # 6. Update immunity
    if person.immunity === nothing
        person.immunity = Immunity()
    end
    add_immunity!(person.immunity, get_immune_to(selector.infection_id))

    return nothing
end

# ---------------------------------------------------------------------------
# InfectionSelectors — multi-variant container
# ---------------------------------------------------------------------------

mutable struct InfectionSelectors
    selectors::Dict{Int, InfectionSelector}   # infection_id → selector
end

InfectionSelectors() = InfectionSelectors(Dict{Int, InfectionSelector}())

function infect_person_at_time!(selectors::InfectionSelectors, person::Person,
                                time::Float64; infection_id::Int=0)
    selector = get(selectors.selectors, infection_id, nothing)
    if selector === nothing
        selector = get(selectors.selectors, 0, nothing)
    end
    selector === nothing && throw(KeyError(infection_id))
    infect_person_at_time!(selector, person, time)
end
