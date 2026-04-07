# ============================================================================
# InfectionSeed — seed initial infections into the population
#
# Included inside `module June`; no sub-module wrapper.
# Assumes InfectionSelector, Person, Population, DataFrames are available.
# ============================================================================

mutable struct InfectionSeed
    infection_selector::InfectionSelector
    daily_cases::DataFrame       # date × region columns with cases per capita per age
    seed_strength::Float64
    min_date::Any
    max_date::Any
end

"""
    InfectionSeed(infection_selector, daily_cases; seed_strength=1.0)

Create a seed from a selector and a DataFrame of daily case counts.
"""
function InfectionSeed(infection_selector::InfectionSelector, daily_cases::DataFrame;
                       seed_strength::Float64=1.0)
    dates = daily_cases[!, 1]
    min_date = minimum(dates)
    max_date = maximum(dates)
    return InfectionSeed(infection_selector, daily_cases, seed_strength, min_date, max_date)
end

"""
    unleash_virus_per_day!(seed::InfectionSeed, world, date, time::Float64, record)

Seed infections for a single day.  Iterates over regions/super-areas in the
daily-cases table and infects a proportional number of susceptible people.
"""
function unleash_virus_per_day!(seed::InfectionSeed, world, date, time::Float64, record)
    # Skip if date is outside seed range
    date < seed.min_date && return nothing
    date > seed.max_date && return nothing

    # Find the row for this date
    row_idx = findfirst(d -> d == date, seed.daily_cases[!, 1])
    row_idx === nothing && return nothing

    row = seed.daily_cases[row_idx, :]

    # Each column after the first is a region/area with cases-per-capita
    for col_name in names(seed.daily_cases)[2:end]
        cases_per_capita = row[col_name]
        if isa(cases_per_capita, Number) && cases_per_capita > 0
            _seed_region!(seed, world, string(col_name), Float64(cases_per_capita), time, record)
        end
    end

    return nothing
end

function _seed_region!(seed::InfectionSeed, world, region_name::String,
                       cases_per_capita::Float64, time::Float64, record)
    world === nothing && return nothing

    targets = Any[]

    if hasproperty(world, :regions) && world.regions !== nothing
        try
            region = get_from_name(world.regions, region_name)
            append!(targets, region.super_areas)
        catch
        end
    end

    if isempty(targets) && hasproperty(world, :super_areas) && world.super_areas !== nothing
        try
            push!(targets, get_from_name(world.super_areas, region_name))
        catch
        end
    end

    if isempty(targets) && hasproperty(world, :areas) && world.areas !== nothing
        try
            area = get_from_name(world.areas, region_name)
            area.super_area !== nothing && push!(targets, area.super_area)
        catch
        end
    end

    isempty(targets) && return nothing

    populations = [length(people(target)) for target in targets]
    total_population = sum(populations)
    total_population == 0 && return nothing

    total_cases = round(Int, cases_per_capita * total_population * seed.seed_strength)
    if total_cases <= 0 && cases_per_capita > 0
        total_cases = 1
    end

    remaining_cases = total_cases
    for i in eachindex(targets)
        populations[i] == 0 && continue

        n_cases = if i == lastindex(targets)
            remaining_cases
        else
            min(
                remaining_cases,
                round(Int, total_cases * populations[i] / total_population),
            )
        end

        n_cases > 0 || continue
        infect_super_area!(seed, targets[i], n_cases, time; record=record)
        remaining_cases -= n_cases
        remaining_cases <= 0 && break
    end

    return nothing
end

"""
    infect_super_area!(seed::InfectionSeed, super_area, n_cases::Int, time::Float64)

Infect `n_cases` random susceptible people in the given super area.
"""
function infect_super_area!(seed::InfectionSeed, super_area, n_cases::Int, time::Float64;
                            record=nothing)
    all_people = people(super_area)
    susceptible = filter(p -> !is_infected(p) && !p.dead, all_people)
    isempty(susceptible) && return nothing

    n_to_infect = min(n_cases, length(susceptible))
    chosen = StatsBase.sample(susceptible, n_to_infect; replace=false)

    for person in chosen
        infect_person_at_time!(seed.infection_selector, person, time)
        if record !== nothing
            accumulate_infection!(
                record;
                person_id=person.id,
                time=time,
                infection_id=seed.infection_selector.infection_id,
                source="seed",
            )
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# InfectionSeeds — container for multi-variant seeding
# ---------------------------------------------------------------------------

mutable struct InfectionSeeds
    seeds::Vector{InfectionSeed}
end

InfectionSeeds() = InfectionSeeds(InfectionSeed[])

"""
    infection_seeds_timestep!(seeds::InfectionSeeds, world, timer, record)

Run all seeds for the current simulation timestep.
"""
function infection_seeds_timestep!(seeds::InfectionSeeds, world, timer, record)
    for seed in seeds.seeds
        unleash_virus_per_day!(seed, world, timer.date, timer.now, record)
    end
    return nothing
end
