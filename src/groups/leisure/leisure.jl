# ---------------------------------------------------------------------------
# Leisure — top-level leisure management
# ---------------------------------------------------------------------------

mutable struct Leisure
    distributors::Dict{String, SocialVenueDistributor}
    residence_visits_distributor::Union{Nothing, ResidenceVisitsDistributor}
end

function Leisure()
    return Leisure(Dict{String, SocialVenueDistributor}(), nothing)
end

"""
    generate_leisure_for_world(world; config_path=nothing) -> Leisure

Create leisure distributors for each venue type present in the world.
"""
function generate_leisure_for_world(world; config_path=nothing)
    leisure = Leisure()

    venue_map = Dict(
        "pubs"      => world.pubs,
        "cinemas"   => world.cinemas,
        "groceries" => world.groceries,
    )

    for (name, venues) in venue_map
        isnothing(venues) && continue
        dist = social_venue_distributor_from_config(name, venues; config_path=config_path)
        leisure.distributors[name] = dist
    end

    return leisure
end

"""
    get_leisure_subgroup(leisure::Leisure, person::Person, spec::String)

Get a leisure subgroup for `person` from the distributor matching `spec`.
"""
function get_leisure_subgroup(leisure::Leisure, person::Person, spec::String)
    haskey(leisure.distributors, spec) || return nothing
    return get_leisure_subgroup(leisure.distributors[spec], person)
end
