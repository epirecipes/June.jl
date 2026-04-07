# ============================================================================
# ActivityManager — assigns people to groups each time-step
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

const ACTIVITY_HIERARCHY = [
    :medical_facility, :rail_travel, :commute,
    :primary_activity, :leisure, :residence
]

mutable struct ActivityManager
    activity_to_super_groups::Dict{String, Vector{String}}
    all_super_groups::Vector{String}
    active_super_groups::Vector{String}
    policies::Any     # Union{Nothing, Policies}
    leisure::Any      # Union{Nothing, Leisure}
    travel::Any       # Union{Nothing, Travel}
end

"""
    activity_manager_from_file(config_path; world=nothing, leisure=nothing,
                               travel=nothing, policies=nothing,
                               timer=nothing, record=nothing)

Construct an `ActivityManager` from a YAML config.
"""
function activity_manager_from_file(config_path::String;
                                    world=nothing, leisure=nothing,
                                    travel=nothing, policies=nothing,
                                    timer=nothing, record=nothing)
    cfg = YAML.load_file(config_path)
    am_cfg = get(cfg, "activity_manager", cfg)

    activity_to_super_groups = Dict{String, Vector{String}}()
    for (act, sgs) in get(am_cfg, "activity_to_super_groups", Dict())
        activity_to_super_groups[String(act)] = String.(sgs)
    end

    all_sgs = unique(vcat(values(activity_to_super_groups)...))

    return ActivityManager(
        activity_to_super_groups,
        all_sgs,
        String[],
        policies,
        leisure,
        travel,
    )
end

"""
    do_timestep!(am::ActivityManager, timer::Timer; world=nothing, record=nothing)

Execute one time-step of activity assignment.
"""
function do_timestep!(am::ActivityManager, timer::Timer;
                      world=nothing, record=nothing)
    current_activities = activities(timer)
    am.active_super_groups = get_active_super_groups(am, current_activities)

    # Clear all active groups
    if world !== nothing
        clear_world_groups!(am, world)
    end

    # Apply leisure policies
    if am.policies !== nothing && am.leisure !== nothing
        try
            apply_leisure!(am.policies, timer.date, am.leisure)
        catch
        end
    end

    # Assign people to subgroups
    if world !== nothing
        move_people_to_active_subgroups!(am, current_activities, world, timer.date)
    end

    return current_activities
end

"""
    get_active_super_groups(am::ActivityManager, current_activities)

Determine which super-groups should be active given the current activities.
"""
function get_active_super_groups(am::ActivityManager, current_activities)
    active = String[]
    for act in current_activities
        for sg in get(am.activity_to_super_groups, act, String[])
            if sg ∉ active
                push!(active, sg)
            end
        end
    end
    return active
end

"""
    clear_world_groups!(am::ActivityManager, world)

Remove all people from active group subgroups before reassignment.
"""
function clear_world_groups!(am::ActivityManager, world)
    for spec in am.all_super_groups
        if hasproperty(world, Symbol(spec))
            sg_collection = getproperty(world, Symbol(spec))
            if sg_collection !== nothing
                try
                    for grp in sg_collection
                        for sg in grp.subgroups
                            for person in sg.people
                                person.busy = false
                            end
                        end
                        clear!(grp)
                    end
                catch
                end
            end
        end
    end
end

"""
    move_people_to_active_subgroups!(am, activities_list, world)

For each person, walk `ACTIVITY_HIERARCHY` and assign to the first matching
activity subgroup that is both in the current activities and available.
"""
function move_people_to_active_subgroups!(am::ActivityManager,
                                          activities_list::Vector{String},
                                          world,
                                          date)
    world.people === nothing && return nothing

    for person in world.people
        if person.dead
            continue
        end

        person_activities = if am.policies === nothing
            activities_list
        else
            apply_individual!(am.policies, person, activities_list, date)
        end
        isempty(person_activities) && continue

        activity_set = Set(Symbol.(person_activities))
        assigned = false
        for activity in ACTIVITY_HIERARCHY
            if activity ∉ activity_set
                continue
            end
            subgroup = getfield(person.subgroups, activity)
            if subgroup === nothing
                continue
            end
            if !is_available(person) && activity != :medical_facility
                continue
            end
            add!(subgroup, person)
            assigned = true
            break
        end
    end
    return nothing
end

function Base.show(io::IO, am::ActivityManager)
    n_act = length(am.activity_to_super_groups)
    n_active = length(am.active_super_groups)
    print(io, "ActivityManager(activities=$n_act, active_groups=$n_active)")
end
