# ---------------------------------------------------------------------------
# Travel — commute and inter-city travel management
# ---------------------------------------------------------------------------

mutable struct Travel
    city_transports::Union{Nothing, CityTransports}
    inter_city_transports::Union{Nothing, InterCityTransports}
    cities::Vector{Any}
end

Travel() = Travel(nothing, nothing, Any[])

"""
    initialise_commute!(travel::Travel, world)

Set up city and inter-city transport infrastructure:
1. Generate cities from super-area data
2. Assign transport modes to working-age people
3. Create stations and transport groups
4. Distribute commuters to stations
"""
function initialise_commute!(travel::Travel, world)
    isnothing(world.super_areas) && return

    # Create transport collections if needed
    if isnothing(travel.city_transports)
        travel.city_transports = Transports("city_transport")
    end
    if isnothing(travel.inter_city_transports)
        travel.inter_city_transports = Transports("inter_city_transport")
    end

    # Stub: full implementation would build city graphs, assign stations,
    # and distribute commuters based on mode-of-transport probabilities.
end
