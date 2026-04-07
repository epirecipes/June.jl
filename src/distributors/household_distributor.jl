# ---------------------------------------------------------------------------
# HouseholdDistributor — create households and assign residents
# ---------------------------------------------------------------------------

struct HouseholdDistributor
    household_composition::Dict   # composition types and distributions
    age_difference_dists::Dict    # age differences for couples / parent-child
end

"""
    household_distributor_from_file(; config_path=nothing) -> HouseholdDistributor

Load household composition rules from YAML config.
"""
function household_distributor_from_file(; config_path=nothing)
    if !isnothing(config_path) && isfile(config_path)
        config = YAML.load_file(config_path)
        composition = get(config, "household_composition", Dict())
        age_diffs   = get(config, "age_difference_dists", Dict())
        return HouseholdDistributor(composition, age_diffs)
    end
    return HouseholdDistributor(Dict(), Dict())
end

"""
    distribute_people_and_households!(hd::HouseholdDistributor, areas) -> Vector{Household}

For each area, create households and assign people respecting composition
constraints. Returns the full vector of created `Household` objects.
"""
function distribute_people_and_households!(hd::HouseholdDistributor, areas)
    all_households = Household[]

    for area in areas.members
        isempty(area.people) && continue

        # Simplified assignment: one person per household (placeholder for
        # full composition logic that groups by family, couple, single, etc.)
        for person in area.people
            h = Household(; area=area)
            add!(h, person; activity=:residence)
            push!(area.households, h)
            push!(all_households, h)
        end
    end
    return all_households
end
