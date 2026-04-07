# ============================================================================
# Geography — Area / SuperArea / Region hierarchy
#
# Included inside `module June`; no sub-module wrapper.
# Assumes Person, Population, DemographyError are already defined.
# ============================================================================

# ---------------------------------------------------------------------------
# ID counters
# ---------------------------------------------------------------------------
const _AREA_ID_COUNTER = Ref(0)
const _SUPER_AREA_ID_COUNTER = Ref(0)
const _REGION_ID_COUNTER = Ref(0)

function _next_area_id()
    _AREA_ID_COUNTER[] += 1
    return _AREA_ID_COUNTER[]
end

function _next_super_area_id()
    _SUPER_AREA_ID_COUNTER[] += 1
    return _SUPER_AREA_ID_COUNTER[]
end

function _next_region_id()
    _REGION_ID_COUNTER[] += 1
    return _REGION_ID_COUNTER[]
end

function reset_geography_counters!()
    _AREA_ID_COUNTER[] = 0
    _SUPER_AREA_ID_COUNTER[] = 0
    _REGION_ID_COUNTER[] = 0
end

# ---------------------------------------------------------------------------
# GeographyError
# ---------------------------------------------------------------------------
struct GeographyError <: Exception
    msg::String
end
Base.showerror(io::IO, e::GeographyError) = print(io, "GeographyError: ", e.msg)

# ---------------------------------------------------------------------------
# Area
# ---------------------------------------------------------------------------
mutable struct Area
    id::Int
    name::String
    coordinates::Tuple{Float64,Float64}   # (latitude, longitude)
    super_area::Any                        # forward ref → SuperArea
    people::Vector{Person}
    schools::Vector{Any}
    households::Vector{Any}
    social_venues::Dict{String,Vector{Any}}
    care_home::Any                         # Union{Nothing, CareHome}
    socioeconomic_index::Float64

    function Area(;
        name::String = "",
        coordinates::Tuple{Float64,Float64} = (0.0, 0.0),
        super_area = nothing,
        socioeconomic_index::Float64 = 0.0,
    )
        new(
            _next_area_id(),
            name,
            coordinates,
            super_area,
            Person[],
            Any[],
            Any[],
            Dict{String,Vector{Any}}(),
            nothing,
            socioeconomic_index,
        )
    end
end

function add!(area::Area, person::Person)
    push!(area.people, person)
    person.area = area
    return nothing
end

function populate!(area::Area, demography, ethnicity, comorbidity)
    # Stub — to be implemented when demography module is complete
    return nothing
end

function region(area::Area)
    area.super_area === nothing && return nothing
    return area.super_area.region
end

Base.show(io::IO, a::Area) = print(io, "Area(id=$(a.id), name=\"$(a.name)\")")

# ---------------------------------------------------------------------------
# SuperArea
# ---------------------------------------------------------------------------
mutable struct SuperArea
    id::Int
    name::String
    coordinates::Tuple{Float64,Float64}
    region::Any                            # forward ref → Region
    areas::Vector{Area}
    city::Any
    workers::Vector{Person}
    companies::Vector{Any}
    closest_hospitals::Vector{Any}
    external::Bool

    function SuperArea(;
        name::String = "",
        coordinates::Tuple{Float64,Float64} = (0.0, 0.0),
        region = nothing,
        areas::Vector{Area} = Area[],
        external::Bool = false,
    )
        new(
            _next_super_area_id(),
            name,
            coordinates,
            region,
            areas,
            nothing,
            Person[],
            Any[],
            Any[],
            external,
        )
    end
end

function add_worker!(sa::SuperArea, person::Person)
    push!(sa.workers, person)
    return nothing
end

function remove_worker!(sa::SuperArea, person::Person)
    filter!(p -> p !== person, sa.workers)
    return nothing
end

function people(sa::SuperArea)
    return reduce(vcat, (a.people for a in sa.areas); init=Person[])
end

function households(sa::SuperArea)
    return reduce(vcat, (a.households for a in sa.areas); init=Any[])
end

Base.show(io::IO, sa::SuperArea) = print(io, "SuperArea(id=$(sa.id), name=\"$(sa.name)\")")

# ---------------------------------------------------------------------------
# ExternalSuperArea
# ---------------------------------------------------------------------------
mutable struct ExternalSuperArea
    id::Int
    domain_id::Int
    coordinates::Tuple{Float64,Float64}
    city::Any
    external::Bool

    function ExternalSuperArea(;
        domain_id::Int = 0,
        coordinates::Tuple{Float64,Float64} = (0.0, 0.0),
    )
        new(
            _next_super_area_id(),
            domain_id,
            coordinates,
            nothing,
            true,
        )
    end
end

Base.show(io::IO, esa::ExternalSuperArea) =
    print(io, "ExternalSuperArea(id=$(esa.id), domain_id=$(esa.domain_id))")

# ---------------------------------------------------------------------------
# Region
# ---------------------------------------------------------------------------
mutable struct Region
    id::Int
    name::String
    super_areas::Vector{SuperArea}
    regional_compliance::Float64
    lockdown_tier::Int
    local_closed_venues::Set{String}
    global_closed_venues::Set{String}
    external::Bool

    function Region(;
        name::String = "",
        super_areas::Vector{SuperArea} = SuperArea[],
        regional_compliance::Float64 = 1.0,
        lockdown_tier::Int = 0,
        external::Bool = false,
    )
        new(
            _next_region_id(),
            name,
            super_areas,
            regional_compliance,
            lockdown_tier,
            Set{String}(),
            Set{String}(),
            external,
        )
    end
end

function people(region::Region)
    return reduce(vcat, (people(sa) for sa in region.super_areas); init=Person[])
end

function closed_venues(region::Region)
    return union(region.local_closed_venues, region.global_closed_venues)
end

function households(region::Region)
    return reduce(vcat, (households(sa) for sa in region.super_areas); init=Any[])
end

Base.show(io::IO, r::Region) = print(io, "Region(id=$(r.id), name=\"$(r.name)\")")

# ============================================================================
# Collection types — Areas, SuperAreas, Regions
# ============================================================================

# ---------------------------------------------------------------------------
# Areas (with spatial queries)
# ---------------------------------------------------------------------------
struct Areas
    members::Vector{Area}
    members_by_id::Dict{Int,Area}
    members_by_name::Dict{String,Area}
    _ball_tree::Ref{Any}         # lazily built BallTree
    _coords_rad::Ref{Any}        # Matrix{Float64} in radians

    function Areas(areas::Vector{Area})
        by_id   = Dict{Int,Area}(a.id => a for a in areas)
        by_name = Dict{String,Area}(a.name => a for a in areas)
        new(areas, by_id, by_name, Ref{Any}(nothing), Ref{Any}(nothing))
    end
end

Areas() = Areas(Area[])

Base.iterate(c::Areas) = iterate(c.members)
Base.iterate(c::Areas, state) = iterate(c.members, state)
Base.length(c::Areas) = length(c.members)
Base.getindex(c::Areas, i::Int) = c.members[i]
Base.eltype(::Type{Areas}) = Area
Base.firstindex(c::Areas) = 1
Base.lastindex(c::Areas) = length(c.members)

get_from_id(c::Areas, id::Int) = c.members_by_id[id]
get_from_name(c::Areas, name::String) = c.members_by_name[name]

function _build_ball_tree!(c::Areas)
    n = length(c.members)
    n == 0 && throw(GeographyError("Cannot build spatial index for empty Areas collection"))
    data = Matrix{Float64}(undef, 2, n)
    for i in 1:n
        data[1, i] = deg2rad(c.members[i].coordinates[1])  # lat
        data[2, i] = deg2rad(c.members[i].coordinates[2])  # lon
    end
    c._coords_rad[] = data
    c._ball_tree[] = BallTree(data, Haversine(6371.0))
    return nothing
end

"""
    get_closest_areas(areas::Areas, coords::Tuple{Float64,Float64}, k::Int)

Return the `k` closest `Area` objects to `coords` (lat, lon in degrees).
Uses a BallTree with Haversine metric (lazily constructed on first call).
"""
function get_closest_areas(c::Areas, coords::Tuple{Float64,Float64}, k::Int)
    if c._ball_tree[] === nothing
        _build_ball_tree!(c)
    end
    query = [deg2rad(coords[1]), deg2rad(coords[2])]
    k_actual = min(k, length(c.members))
    idxs, dists = knn(c._ball_tree[], query, k_actual)
    return [(c.members[i], dists[j]) for (j, i) in enumerate(idxs)]
end

Base.show(io::IO, c::Areas) = print(io, "Areas(n=$(length(c.members)))")

# ---------------------------------------------------------------------------
# SuperAreas (with spatial queries)
# ---------------------------------------------------------------------------
struct SuperAreas
    members::Vector{SuperArea}
    members_by_id::Dict{Int,SuperArea}
    members_by_name::Dict{String,SuperArea}
    _ball_tree::Ref{Any}
    _coords_rad::Ref{Any}

    function SuperAreas(sas::Vector{SuperArea})
        by_id   = Dict{Int,SuperArea}(sa.id => sa for sa in sas)
        by_name = Dict{String,SuperArea}(sa.name => sa for sa in sas)
        new(sas, by_id, by_name, Ref{Any}(nothing), Ref{Any}(nothing))
    end
end

SuperAreas() = SuperAreas(SuperArea[])

Base.iterate(c::SuperAreas) = iterate(c.members)
Base.iterate(c::SuperAreas, state) = iterate(c.members, state)
Base.length(c::SuperAreas) = length(c.members)
Base.getindex(c::SuperAreas, i::Int) = c.members[i]
Base.eltype(::Type{SuperAreas}) = SuperArea
Base.firstindex(c::SuperAreas) = 1
Base.lastindex(c::SuperAreas) = length(c.members)

get_from_id(c::SuperAreas, id::Int) = c.members_by_id[id]
get_from_name(c::SuperAreas, name::String) = c.members_by_name[name]

function _build_ball_tree!(c::SuperAreas)
    n = length(c.members)
    n == 0 && throw(GeographyError("Cannot build spatial index for empty SuperAreas collection"))
    data = Matrix{Float64}(undef, 2, n)
    for i in 1:n
        data[1, i] = deg2rad(c.members[i].coordinates[1])
        data[2, i] = deg2rad(c.members[i].coordinates[2])
    end
    c._coords_rad[] = data
    c._ball_tree[] = BallTree(data, Haversine(6371.0))
    return nothing
end

function get_closest_super_areas(c::SuperAreas, coords::Tuple{Float64,Float64}, k::Int)
    if c._ball_tree[] === nothing
        _build_ball_tree!(c)
    end
    query = [deg2rad(coords[1]), deg2rad(coords[2])]
    k_actual = min(k, length(c.members))
    idxs, dists = knn(c._ball_tree[], query, k_actual)
    return [(c.members[i], dists[j]) for (j, i) in enumerate(idxs)]
end

Base.show(io::IO, c::SuperAreas) = print(io, "SuperAreas(n=$(length(c.members)))")

# ---------------------------------------------------------------------------
# Regions (no spatial queries needed)
# ---------------------------------------------------------------------------
struct Regions
    members::Vector{Region}
    members_by_id::Dict{Int,Region}
    members_by_name::Dict{String,Region}

    function Regions(regions::Vector{Region})
        by_id   = Dict{Int,Region}(r.id => r for r in regions)
        by_name = Dict{String,Region}(r.name => r for r in regions)
        new(regions, by_id, by_name)
    end
end

Regions() = Regions(Region[])

Base.iterate(c::Regions) = iterate(c.members)
Base.iterate(c::Regions, state) = iterate(c.members, state)
Base.length(c::Regions) = length(c.members)
Base.getindex(c::Regions, i::Int) = c.members[i]
Base.eltype(::Type{Regions}) = Region
Base.firstindex(c::Regions) = 1
Base.lastindex(c::Regions) = length(c.members)

get_from_id(c::Regions, id::Int) = c.members_by_id[id]
get_from_name(c::Regions, name::String) = c.members_by_name[name]

Base.show(io::IO, c::Regions) = print(io, "Regions(n=$(length(c.members)))")

# ============================================================================
# Geography — top-level container
# ============================================================================
mutable struct Geography
    areas::Areas
    super_areas::SuperAreas
    regions::Regions
    # Optional group fields (populated later by distributors)
    households::Any
    schools::Any
    hospitals::Any
    companies::Any
    care_homes::Any
    pubs::Any
    cinemas::Any
    groceries::Any
    universities::Any

    function Geography(areas::Areas, super_areas::SuperAreas, regions::Regions)
        new(areas, super_areas, regions,
            nothing, nothing, nothing, nothing, nothing,
            nothing, nothing, nothing, nothing)
    end
end

Base.show(io::IO, g::Geography) = print(
    io,
    "Geography(areas=$(length(g.areas)), super_areas=$(length(g.super_areas)), regions=$(length(g.regions)))",
)

# ============================================================================
# Building geography from DataFrames
# ============================================================================

"""
    create_geographical_units(hierarchy_df, area_coords_df, super_area_coords_df, socioeconomic_df)

Build the full Area → SuperArea → Region hierarchy from DataFrames.
Returns `(Areas, SuperAreas, Regions)`.
"""
function create_geographical_units(
    hierarchy_df::DataFrame,
    area_coords_df::DataFrame,
    super_area_coords_df::DataFrame,
    socioeconomic_df::DataFrame,
)
    # Index coordinate and socioeconomic data for fast lookup
    area_coords = Dict{String,Tuple{Float64,Float64}}()
    for row in eachrow(area_coords_df)
        area_coords[string(row[1])] = (Float64(row[2]), Float64(row[3]))
    end

    sa_coords = Dict{String,Tuple{Float64,Float64}}()
    for row in eachrow(super_area_coords_df)
        sa_coords[string(row[1])] = (Float64(row[2]), Float64(row[3]))
    end

    socioeco = Dict{String,Float64}()
    for row in eachrow(socioeconomic_df)
        socioeco[string(row[1])] = Float64(row[2])
    end

    # Determine column names in the hierarchy DataFrame
    col_names = names(hierarchy_df)
    area_col = col_names[1]
    super_area_col = col_names[2]
    region_col = col_names[3]

    # Build hierarchy: Region → SuperArea → Area
    all_areas = Area[]
    all_super_areas = SuperArea[]
    all_regions = Region[]

    region_map = Dict{String,Region}()
    sa_map = Dict{String,SuperArea}()

    for row in eachrow(hierarchy_df)
        area_name = string(row[area_col])
        sa_name = string(row[super_area_col])
        region_name = string(row[region_col])

        # Get or create Region
        if !haskey(region_map, region_name)
            r = Region(; name=region_name)
            region_map[region_name] = r
            push!(all_regions, r)
        end
        rgn = region_map[region_name]

        # Get or create SuperArea
        if !haskey(sa_map, sa_name)
            coords = get(sa_coords, sa_name, (0.0, 0.0))
            sa = SuperArea(; name=sa_name, coordinates=coords, region=rgn)
            sa_map[sa_name] = sa
            push!(all_super_areas, sa)
            push!(rgn.super_areas, sa)
        end
        sarea = sa_map[sa_name]

        # Create Area
        coords = get(area_coords, area_name, (0.0, 0.0))
        sei = get(socioeco, area_name, 0.0)
        a = Area(; name=area_name, coordinates=coords, super_area=sarea, socioeconomic_index=sei)
        push!(all_areas, a)
        push!(sarea.areas, a)
    end

    return (Areas(all_areas), SuperAreas(all_super_areas), Regions(all_regions))
end

# ============================================================================
# File-based construction
# ============================================================================

# Default file paths
_default_hierarchy_file() = joinpath(data_path(), "input", "geography", "area_super_area_region.csv")
_default_area_coords_file() = joinpath(data_path(), "input", "geography", "area_coordinates_sorted.csv")
_default_super_area_coords_file() = joinpath(data_path(), "input", "geography", "super_area_coordinates_sorted.csv")
_default_socioeconomic_file() = joinpath(data_path(), "input", "geography", "socioeconomic_index.csv")

"""
    geography_from_file(; filter_key=nothing, hierarchy_filename=nothing,
                          area_coords_filename=nothing, super_area_coords_filename=nothing,
                          socioeconomic_filename=nothing)

Load geography from CSV files and build the Area/SuperArea/Region hierarchy.

`filter_key` is an optional `Dict{String,Vector{String}}` to subset the hierarchy,
e.g. `Dict("region" => ["North East"])` or `Dict("super_area" => ["E02004940"])`.
"""
function geography_from_file(;
    filter_key::Union{Nothing,Dict{String,<:AbstractVector{<:AbstractString}}} = nothing,
    hierarchy_filename::Union{Nothing,String} = nothing,
    area_coords_filename::Union{Nothing,String} = nothing,
    super_area_coords_filename::Union{Nothing,String} = nothing,
    socioeconomic_filename::Union{Nothing,String} = nothing,
)
    h_file  = something(hierarchy_filename,        _default_hierarchy_file())
    ac_file = something(area_coords_filename,      _default_area_coords_file())
    sc_file = something(super_area_coords_filename, _default_super_area_coords_file())
    se_file = something(socioeconomic_filename,    _default_socioeconomic_file())

    hierarchy_df       = CSV.read(h_file,  DataFrame)
    area_coords_df     = CSV.read(ac_file, DataFrame)
    super_area_coords_df = CSV.read(sc_file, DataFrame)
    socioeconomic_df   = CSV.read(se_file, DataFrame)

    # Apply filter if provided
    if filter_key !== nothing
        hierarchy_df = _apply_geography_filter(hierarchy_df, filter_key)
    end

    areas, super_areas, regions = create_geographical_units(
        hierarchy_df, area_coords_df, super_area_coords_df, socioeconomic_df,
    )

    return Geography(areas, super_areas, regions)
end

"""
    _apply_geography_filter(df, filter_key)

Filter the hierarchy DataFrame by the given keys.
Supported filter keys: "area", "super_area", "region".
"""
function _apply_geography_filter(
    df::DataFrame,
    filter_key::Dict{String,<:AbstractVector{<:AbstractString}},
)
    col_names = names(df)
    area_col = col_names[1]
    super_area_col = col_names[2]
    region_col = col_names[3]

    key_to_col = Dict(
        "area"       => area_col,
        "super_area" => super_area_col,
        "region"     => region_col,
    )

    result = df
    for (key, values) in filter_key
        col = get(key_to_col, key, nothing)
        if col === nothing
            throw(GeographyError("Unknown filter key '$key'. Use one of: area, super_area, region"))
        end
        result = filter(row -> string(row[col]) in values, result)
    end

    if nrow(result) == 0
        throw(GeographyError("Filter produced empty hierarchy. Check filter_key values."))
    end

    return result
end
