# ============================================================================
# Infection & Immunity
#
# Included inside `module June`; no sub-module wrapper.
# Assumes AbstractTransmission, Symptoms, update_infection_probability!,
# update_trajectory_stage!, SymptomTag predicates are already defined.
# ============================================================================

# ---------------------------------------------------------------------------
# Infection
# ---------------------------------------------------------------------------
mutable struct Infection
    transmission::AbstractTransmission
    symptoms::Symptoms
    start_time::Float64
    infection_id::Int       # variant identifier
    time_of_testing::Float64
end

function Infection(transmission::AbstractTransmission, symptoms::Symptoms,
                   start_time::Float64; infection_id::Int=0)
    return Infection(transmission, symptoms, start_time, infection_id, -1.0)
end

"""
    update_health_status!(inf::Infection, time::Float64, delta_time::Float64)::Symbol

Advance the infection by one timestep.  Returns `:infected`, `:recovered`,
or `:dead`.
"""
function update_health_status!(inf::Infection, time::Float64, delta_time::Float64)::Symbol
    time_from_infection = time - inf.start_time
    update_infection_probability!(inf.transmission, time_from_infection)
    update_trajectory_stage!(inf.symptoms, time_from_infection)
    if is_dead(inf.symptoms)
        return :dead
    elseif is_recovered(inf.symptoms)
        return :recovered
    else
        return :infected
    end
end

infection_probability(inf::Infection) = inf.transmission.probability
tag(inf::Infection) = inf.symptoms.tag

function should_be_in_hospital(inf::Infection)
    return should_be_in_hospital(inf.symptoms.tag)
end

# ---------------------------------------------------------------------------
# Immunity
# ---------------------------------------------------------------------------
mutable struct Immunity
    susceptibility_dict::Dict{Int, Float64}       # infection_id → susceptibility (0=immune, 1=fully susceptible)
    effective_multiplier_dict::Dict{Int, Float64}  # infection_id → severity multiplier
end

function Immunity(; susceptibility_dict=nothing, effective_multiplier_dict=nothing)
    s = isnothing(susceptibility_dict)  ? Dict{Int, Float64}() : susceptibility_dict
    m = isnothing(effective_multiplier_dict) ? Dict{Int, Float64}() : effective_multiplier_dict
    return Immunity(s, m)
end

get_susceptibility(imm::Immunity, infection_id::Int) =
    get(imm.susceptibility_dict, infection_id, 1.0)

get_effective_multiplier(imm::Immunity, infection_id::Int) =
    get(imm.effective_multiplier_dict, infection_id, 1.0)

function add_immunity!(imm::Immunity, infection_ids::Vector{Int})
    for id in infection_ids
        imm.susceptibility_dict[id] = 0.0
    end
    return nothing
end

is_immune(imm::Immunity, infection_id::Int) =
    get_susceptibility(imm, infection_id) == 0.0
