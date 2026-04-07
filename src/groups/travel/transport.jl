# ---------------------------------------------------------------------------
# Transport — group for commuters on a transport link
# ---------------------------------------------------------------------------

mutable struct Transport
    group::Group
    station::Any
end

function Transport(spec::String; station=nothing)
    return Transport(Group(spec, 1), station)
end

const CityTransport      = Transport
const InterCityTransport = Transport

# ---------------------------------------------------------------------------
# Transports — collection of transport groups
# ---------------------------------------------------------------------------

mutable struct Transports
    spec::String
    members::Vector{Transport}
end

function Transports(spec::String)
    return Transports(spec, Transport[])
end

const CityTransports      = Transports
const InterCityTransports = Transports

Base.length(ts::Transports) = length(ts.members)
Base.iterate(ts::Transports) = iterate(ts.members)
Base.iterate(ts::Transports, state) = iterate(ts.members, state)
Base.getindex(ts::Transports, i) = ts.members[i]
Base.push!(ts::Transports, t::Transport) = push!(ts.members, t)
