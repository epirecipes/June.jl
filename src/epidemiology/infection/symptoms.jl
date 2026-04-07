# ============================================================================
# Symptoms — health trajectory for an infected person
#
# Included inside `module June`; no sub-module wrapper.
# Assumes SymptomTag, symptom_from_value, is_dead (from symptom_tag.jl) are
# already defined.
# ============================================================================

mutable struct Symptoms
    tag::SymptomTag
    max_tag::SymptomTag
    max_severity::Float64
    trajectory::Vector{Tuple{Float64, SymptomTag}}   # (completion_time, tag)
    stage::Int
    time_of_symptoms_onset::Float64
end

"""
    Symptoms(health_index::Vector{Float64})

Create symptoms with a random severity draw against `health_index`
(a cumulative probability array for outcome thresholds).
"""
function Symptoms(health_index::Vector{Float64})
    max_severity = rand()
    max_tag_idx = searchsortedfirst(health_index, max_severity) - 1
    max_tag_idx = clamp(max_tag_idx, 0, length(health_index))
    max_tag = symptom_from_value(max_tag_idx)
    return Symptoms(exposed, max_tag, max_severity,
                    Tuple{Float64, SymptomTag}[], 1, -1.0)
end

# ---------------------------------------------------------------------------
# Trajectory management
# ---------------------------------------------------------------------------

"""
    set_trajectory!(s::Symptoms, trajectory::Vector{Tuple{Float64, SymptomTag}})

Assign a pre-built trajectory and determine the time of symptoms onset
(first stage whose tag ≥ mild).
"""
function set_trajectory!(s::Symptoms, trajectory::Vector{Tuple{Float64, SymptomTag}})
    s.trajectory = trajectory
    s.stage = 1
    s.time_of_symptoms_onset = -1.0
    cumulative = 0.0
    for (dt, tag) in trajectory
        cumulative += dt
        if symptom_value(tag) >= symptom_value(mild) && s.time_of_symptoms_onset < 0.0
            s.time_of_symptoms_onset = cumulative
        end
    end
    return nothing
end

"""
    update_trajectory_stage!(s::Symptoms, time_from_infection::Float64)

Advance through trajectory stages based on elapsed time since infection.
Updates `s.tag` and `s.stage`.
"""
function update_trajectory_stage!(s::Symptoms, time_from_infection::Float64)
    n = length(s.trajectory)
    n == 0 && return nothing

    cumulative = 0.0
    for i in 1:(s.stage - 1)
        i > n && break
        cumulative += s.trajectory[i][1]
    end

    while s.stage <= n
        stage_end = cumulative + s.trajectory[s.stage][1]
        if time_from_infection >= stage_end
            s.tag = s.trajectory[s.stage][2]
            cumulative = stage_end
            s.stage += 1
        else
            break
        end
    end

    if s.stage > n
        if is_dead(s.tag)
            # already set to dead tag
        else
            s.tag = recovered
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Predicates
# ---------------------------------------------------------------------------

is_dead(s::Symptoms) = is_dead(s.tag)
is_recovered(s::Symptoms) = s.tag == recovered
