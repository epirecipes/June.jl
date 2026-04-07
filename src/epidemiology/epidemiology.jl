# ============================================================================
# Epidemiology_ — top-level orchestrator
#
# Included inside `module June`; no sub-module wrapper.
# Named Epidemiology_ to avoid conflict with the directory name.
# Assumes all infection/immunity/vaccine types are already defined.
# ============================================================================

mutable struct Epidemiology_
    infection_selectors::Union{Nothing, InfectionSelectors}
    infection_seeds::Union{Nothing, InfectionSeeds}
    immunity_setter::Union{Nothing, ImmunitySetter}
    vaccination_campaigns::Union{Nothing, VaccinationCampaigns}
end

Epidemiology_() = Epidemiology_(nothing, nothing, nothing, nothing)

_population(world) = hasproperty(world, :people) ? world.people : nothing

# ---------------------------------------------------------------------------
# Main timestep
# ---------------------------------------------------------------------------

"""
    do_timestep!(epi::Epidemiology_, world, timer, record;
                 infected_ids=Int[], infection_ids=Int[])

Run one epidemiology timestep:
1. Infect newly exposed people.
2. Update health status of all currently infected people.
"""
function do_timestep!(epi::Epidemiology_, world, timer, record;
                      infected_ids::Vector{Int}=Int[],
                      infection_ids::Vector{Int}=Int[])
    apply_vaccinations!(epi, world, timer.date, record)
    infect_people!(epi, world, timer.now, infected_ids, infection_ids, record)
    update_health_status!(epi, world, timer, record)
    return nothing
end

# ---------------------------------------------------------------------------
# Infect newly exposed people
# ---------------------------------------------------------------------------

"""
    infect_people!(epi::Epidemiology_, world, time, infected_ids, infection_ids)

Infect each person whose ID is in `infected_ids` using the appropriate
`InfectionSelector` (variant given by the corresponding entry in
`infection_ids`).
"""
function infect_people!(epi::Epidemiology_, world, time::Float64,
                        infected_ids::Vector{Int}, infection_ids::Vector{Int},
                        record)
    epi.infection_selectors === nothing && return nothing
    length(infected_ids) == 0 && return nothing

    pop = _population(world)
    pop === nothing && return nothing
    for i in eachindex(infected_ids)
        pid = infected_ids[i]
        iid = length(infection_ids) >= i ? infection_ids[i] : 0

        person = try
            get_from_id(pop, pid)
        catch
            continue
        end

        is_infected(person) && continue
        person.dead && continue

        infect_person_at_time!(epi.infection_selectors, person, time; infection_id=iid)
        if record !== nothing
            accumulate_infection!(
                record;
                person_id=person.id,
                time=time,
                infection_id=iid,
                source="transmission",
            )
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Update health status for all infected people
# ---------------------------------------------------------------------------

"""
    update_health_status!(epi::Epidemiology_, world, timer, record)

For every infected person, advance their infection by one timestep.
Handle recovery and death transitions.
"""
function update_health_status!(epi::Epidemiology_, world, timer, record)
    pop = _population(world)
    pop === nothing && return nothing
    delta_time = timer.delta_time
    time = timer.now

    to_bury = Person[]

    for person in pop
        person.infection === nothing && continue

        status = update_health_status!(person.infection, time, delta_time)

        if status == :recovered
            recover!(person, record)
        elseif status == :dead
            push!(to_bury, person)
        end
    end

    for person in to_bury
        bury_the_dead!(world, person, record)
    end

    return nothing
end

# ---------------------------------------------------------------------------
# Recovery
# ---------------------------------------------------------------------------

"""
    recover!(person::Person, record)

Clear the infection and mark the person as recovered.
"""
function recover!(person::Person, record)
    person.infection = nothing
    if record !== nothing
        accumulate_recovery!(record; person_id=person.id)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Death
# ---------------------------------------------------------------------------

"""
    bury_the_dead!(world, person::Person, record)

Mark the person as dead, clear their infection, and move them to the cemetery.
"""
function bury_the_dead!(world, person::Person, record)
    person.dead = true
    person.infection = nothing

    # Remove from all activity subgroups
    for field in activity_fields()
        sg = getfield(person.subgroups, field)
        if sg !== nothing
            try
                remove!(sg, person)
            catch
            end
            setfield!(person.subgroups, field, nothing)
        end
    end

    # Add to cemetery if available
    if hasproperty(world, :cemeteries) && world.cemeteries !== nothing
        try
            add!(world.cemeteries, person)
        catch
        end
    end

    if record !== nothing
        accumulate_death!(record; person_id=person.id)
    end

    return nothing
end

function apply_vaccinations!(epi::Epidemiology_, world, date, record)
    pop = _population(world)
    pop === nothing && return nothing

    for person in pop
        person.dead && continue

        if epi.vaccination_campaigns !== nothing && !is_infected(person)
            apply!(epi.vaccination_campaigns, person, date, record)
        end

        if person.vaccine_trajectory !== nothing
            update_vaccine_effect!(person.vaccine_trajectory, person, date, record)
        end
    end

    return nothing
end
