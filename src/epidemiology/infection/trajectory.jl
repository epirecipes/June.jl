# ============================================================================
# TrajectoryMaker — build symptom trajectories from config
#
# Included inside `module June`; no sub-module wrapper.
# Assumes SymptomTag, symptom_from_string, sample_parameter, YAML are available.
# ============================================================================

struct TrajectoryMaker
    trajectories::Dict{SymptomTag, Vector{Vector{Tuple{String, Dict}}}}
    # max_tag → list of possible trajectory templates
    # each template is a list of (tag_name, duration_config) pairs
end

"""
    trajectory_maker_from_file(config_path::String)

Load a `TrajectoryMaker` from a YAML file.

Expected format:
```yaml
asymptomatic:
  - - ["exposed", {type: "normal", mean: 3.0, std: 0.5}]
    - ["asymptomatic", {type: "normal", mean: 5.0, std: 1.0}]
    - ["recovered", {type: "normal", mean: 0.0, std: 0.0}]
mild:
  - - ["exposed", ...]
    ...
```
"""
function trajectory_maker_from_file(config_path::String)
    config = YAML.load_file(config_path)
    trajectories = Dict{SymptomTag, Vector{Vector{Tuple{String, Dict}}}}()

    for (tag_name, templates) in config
        tag = symptom_from_string(tag_name)
        parsed_templates = Vector{Tuple{String, Dict}}[]
        for template in templates
            stages = Tuple{String, Dict}[]
            for stage in template
                if isa(stage, AbstractVector) && length(stage) >= 2
                    sname = string(stage[1])
                    dur_config = isa(stage[2], Dict) ? stage[2] : Dict("type" => "constant", "value" => stage[2])
                    push!(stages, (sname, dur_config))
                end
            end
            push!(parsed_templates, stages)
        end
        trajectories[tag] = parsed_templates
    end

    return TrajectoryMaker(trajectories)
end

"""
    make_trajectory(tm::TrajectoryMaker, max_tag::SymptomTag)::Vector{Tuple{Float64, SymptomTag}}

Sample a concrete trajectory (durations + tags) for the given `max_tag`.
Randomly selects one of the available templates, then samples each stage
duration from its config distribution.
"""
function make_trajectory(tm::TrajectoryMaker, max_tag::SymptomTag)::Vector{Tuple{Float64, SymptomTag}}
    if !haskey(tm.trajectories, max_tag)
        return Tuple{Float64, SymptomTag}[]
    end

    templates = tm.trajectories[max_tag]
    isempty(templates) && return Tuple{Float64, SymptomTag}[]

    # Choose one template at random
    template = templates[rand(1:length(templates))]

    trajectory = Tuple{Float64, SymptomTag}[]
    for (tag_name, dur_config) in template
        tag = symptom_from_string(tag_name)
        duration = _sample_duration(dur_config)
        duration = max(duration, 0.0)
        push!(trajectory, (duration, tag))
    end

    return trajectory
end

"""Sample a duration from a config dictionary."""
function _sample_duration(config::Dict)
    if haskey(config, "type")
        return sample_parameter(config)
    elseif haskey(config, "value")
        return Float64(config["value"])
    else
        return 0.0
    end
end
