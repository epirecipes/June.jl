# ---------------------------------------------------------------------------
# SocialVenueDistributor — probabilistic leisure assignment
# ---------------------------------------------------------------------------

struct SocialVenueDistributor
    spec::String
    venues::SocialVenues
    times_per_week::Dict       # config for visit frequency
    maximum_distance::Float64
    nearest_venues_to_visit::Int
end

"""
    social_venue_distributor_from_config(spec, venues; config_path=nothing) -> SocialVenueDistributor

Load visit-frequency and spatial parameters from YAML config.
"""
function social_venue_distributor_from_config(spec::String, venues::SocialVenues;
                                              config_path=nothing)
    times_per_week = Dict()
    max_dist = 50.0
    n_nearest = 5

    if !isnothing(config_path) && isfile(config_path)
        config = YAML.load_file(config_path)
        venue_cfg = get(config, spec, Dict())
        times_per_week = get(venue_cfg, "times_per_week", Dict())
        max_dist       = get(venue_cfg, "maximum_distance", 50.0)
        n_nearest      = get(venue_cfg, "nearest_venues_to_visit", 5)
    end

    return SocialVenueDistributor(spec, venues, times_per_week, max_dist, n_nearest)
end

"""
    get_leisure_subgroup(svd::SocialVenueDistributor, person::Person)

Probabilistic venue assignment based on Poisson sampling and spatial proximity.
Returns a `Subgroup` or `nothing`.
"""
function get_leisure_subgroup(svd::SocialVenueDistributor, person::Person)
    isempty(svd.venues.members) && return nothing
    # Simplified: random venue selection (full version uses spatial + Poisson)
    venue = rand(svd.venues.members)
    return venue.group.subgroups[1]
end
