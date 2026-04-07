# ---------------------------------------------------------------------------
# SocialVenue — generic leisure venue group
# ---------------------------------------------------------------------------

mutable struct SocialVenue
    group::Group
end

function SocialVenue(spec::String; area=nothing)
    g = Group(spec, 1; area=area)  # 1 subgroup for leisure
    return SocialVenue(g)
end

function add!(sv::SocialVenue, person::Person)
    add!(sv.group, person, 1)
    person.subgroups.leisure = sv.group.subgroups[1]
end

people(sv::SocialVenue) = people(sv.group)

# ---------------------------------------------------------------------------
# SocialVenues — collection with spatial index
# ---------------------------------------------------------------------------

mutable struct SocialVenues
    spec::String
    members::Vector{SocialVenue}
    members_by_id::Dict{Int, SocialVenue}
    ball_tree::Any   # BallTree for spatial queries
    coordinates::Vector{Tuple{Float64, Float64}}
end

function SocialVenues(spec::String, venues::Vector{SocialVenue}=SocialVenue[])
    members_by_id = Dict(sv.group.id => sv for sv in venues)
    coords = Tuple{Float64,Float64}[]
    for sv in venues
        if !isnothing(sv.group.area)
            push!(coords, sv.group.area.coordinates)
        end
    end
    return SocialVenues(spec, venues, members_by_id, nothing, coords)
end

Base.length(svs::SocialVenues) = length(svs.members)
Base.iterate(svs::SocialVenues) = iterate(svs.members)
Base.iterate(svs::SocialVenues, state) = iterate(svs.members, state)
Base.getindex(svs::SocialVenues, i) = svs.members[i]
Base.push!(svs::SocialVenues, sv::SocialVenue) = push!(svs.members, sv)
