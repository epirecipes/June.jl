# ---------------------------------------------------------------------------
# Simulator — main simulation driver
# ---------------------------------------------------------------------------

mutable struct Simulator
    world::World
    interaction::Interaction
    timer::Timer
    activity_manager::ActivityManager
    epidemiology::Union{Nothing, Epidemiology_}
    tracker::Union{Nothing, Tracker}
    events::Union{Nothing, Events}
    record::Union{Nothing, Record}
    checkpoint_save_dates::Vector{Date}
    checkpoint_save_path::String
end

# ---------------------------------------------------------------------------
# Constructor
# ---------------------------------------------------------------------------

"""
    simulator_from_file(world, interaction; ...) -> Simulator

Build a `Simulator` from config files, wiring together all subsystems.
"""
function simulator_from_file(world::World, interaction::Interaction;
                              policies=nothing, events=nothing,
                              epidemiology=nothing, tracker=nothing,
                              leisure=nothing, travel=nothing,
                              config_path=nothing, record=nothing)
    if isnothing(config_path)
        config_path = default_config_path("config_example.yaml")
    end

    timer = timer_from_file(config_path)
    activity_manager = activity_manager_from_file(config_path;
        world=world, leisure=leisure, travel=travel,
        policies=policies, timer=timer, record=record)

    checkpoint_dates = _read_checkpoint_dates(config_path)

    return Simulator(world, interaction, timer, activity_manager,
                     epidemiology, tracker, events, record,
                     checkpoint_dates, "results/checkpoints")
end

"""
    _read_checkpoint_dates(config_path) -> Vector{Date}

Read optional checkpoint-save dates from the YAML config.
"""
function _read_checkpoint_dates(config_path)::Vector{Date}
    !isfile(config_path) && return Date[]
    config = YAML.load_file(config_path)
    dates_raw = get(config, "checkpoint_save_dates", nothing)
    isnothing(dates_raw) && return Date[]

    if isa(dates_raw, Date)
        return [dates_raw]
    elseif isa(dates_raw, String)
        return [Date(dates_raw, "yyyy-mm-dd")]
    elseif isa(dates_raw, Vector)
        return [isa(d, String) ? Date(d, "yyyy-mm-dd") : Date(d) for d in dates_raw]
    end
    return Date[]
end

# ---------------------------------------------------------------------------
# Main simulation loop
# ---------------------------------------------------------------------------

"""
    run!(sim::Simulator)

Execute the full simulation from `sim.timer.date` to `sim.timer.final_date`.
"""
function run!(sim::Simulator)
    @info "Starting simulation for $(sim.timer.total_days) days at $(sim.timer.date)"
    clear_world!(sim)

    if !isnothing(sim.epidemiology) && !isnothing(sim.epidemiology.immunity_setter)
        set_immunity!(sim.epidemiology.immunity_setter, sim.world)
    end

    if !isnothing(sim.record) && sim.record.record_static_data
        static_data!(sim.record, sim.world)
    end

    while sim.timer.date < sim.timer.final_date
        # Seed infections
        if !isnothing(sim.epidemiology) && !isnothing(sim.epidemiology.infection_seeds)
            infection_seeds_timestep!(sim.epidemiology.infection_seeds, sim.world, sim.timer, sim.record)
        end

        # Do timestep
        do_timestep!(sim)

        # Save checkpoint if needed
        if Date(sim.timer.date) in sim.checkpoint_save_dates
            @info "Saving checkpoint at $(Date(sim.timer.date))"
            save_checkpoint(sim)
        end

        # Advance timer
        advance!(sim.timer)
    end
    @info "Simulation complete"
end

# ---------------------------------------------------------------------------
# Single timestep
# ---------------------------------------------------------------------------

function do_timestep!(sim::Simulator)
    # 1. Apply interaction policies
    if !isnothing(sim.activity_manager.policies)
        apply_interaction!(sim.activity_manager.policies, sim.timer.date, sim.interaction)
        apply_regional_compliance!(sim.activity_manager.policies, sim.timer.date, sim.world.regions)
    end

    # 2. Apply events
    if !isnothing(sim.events)
        apply_events!(sim.events; date=sim.timer.date, world=sim.world,
                      activities=activities(sim.timer), day_type=day_type(sim.timer),
                      simulator=sim)
    end

    current_activities = activities(sim.timer)
    isnothing(current_activities) && return

    # 3. Activity manager moves people
    do_timestep!(sim.activity_manager, sim.timer; world=sim.world, record=sim.record)

    # 4. Interaction loop
    active_sgs   = sim.activity_manager.active_super_groups
    infected_ids  = Int[]
    infection_ids = Int[]
    n_people      = 0

    # Count cemetery
    if !isnothing(sim.world.cemeteries)
        for cem in sim.world.cemeteries.members
            n_people += length(people(cem))
        end
    end

    for sg_name in active_sgs
        occursin("visits", sg_name) && continue
        sg_instance = getfield(sim.world, Symbol(sg_name))
        isnothing(sg_instance) && continue

        for group in sg_instance.members
            group.external && continue
            new_infected, new_infections, group_size = time_step_for_group!(
                sim.interaction, group;
                delta_time=sim.timer.duration, record=sim.record)
            append!(infected_ids, new_infected)
            append!(infection_ids, new_infections)
            n_people += group_size
        end
    end

    # 5. Tracker
    if !isnothing(sim.tracker)
        active_super_groups = [
            getproperty(sim.world, Symbol(name))
            for name in sim.activity_manager.active_super_groups
            if hasproperty(sim.world, Symbol(name)) &&
               !isnothing(getproperty(sim.world, Symbol(name)))
        ]
        tracker_timestep!(sim.tracker, active_super_groups, sim.timer)
    end

    # 6. Epidemiology
    if !isnothing(sim.epidemiology)
        do_timestep!(sim.epidemiology, sim.world, sim.timer, sim.record;
                     infected_ids=infected_ids, infection_ids=infection_ids)
    end

    if !isnothing(sim.record)
        time_step!(sim.record, sim.timer.date)
    end

    # 7. Clear world
    clear_world!(sim)
end

# ---------------------------------------------------------------------------
# clear_world! — reset group memberships between timesteps
# ---------------------------------------------------------------------------

function clear_world!(sim::Simulator)
    for sg_name in sim.activity_manager.all_super_groups
        occursin("visits", sg_name) && continue
        sg_instance = getfield(sim.world, Symbol(sg_name))
        isnothing(sg_instance) && continue
        for group in sg_instance.members
            clear!(group)
        end
    end

    if !isnothing(sim.world.people)
        for person in sim.world.people.people
            person.busy = false
            person.subgroups.leisure = nothing
        end
    end
end

# ---------------------------------------------------------------------------
# Checkpoint saving (stub)
# ---------------------------------------------------------------------------

function save_checkpoint(sim::Simulator)
    @info "Checkpoint saving not yet implemented"
end
