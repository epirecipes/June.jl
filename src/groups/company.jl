# ============================================================================
# Company — workplace group with a single worker subgroup
#
# Included inside `module June`; no sub-module wrapper.
# Subgroups: 1=workers
# ============================================================================

# ── Struct ───────────────────────────────────────────────────────────────

mutable struct Company
    group::Group
    sector::Union{Nothing, String}
    n_workers_max::Int
end

# ── Constructor ──────────────────────────────────────────────────────────

"""
    Company(; sector=nothing, n_workers_max=0, area=nothing)

Create a company with one subgroup (workers).
"""
function Company(; sector=nothing, n_workers_max::Int=0, area=nothing)
    g = Group("company", 1; area=area)
    return Company(g, sector, n_workers_max)
end

# ── Property delegation ──────────────────────────────────────────────────

function Base.getproperty(c::Company, s::Symbol)
    if s in (:group, :sector, :n_workers_max)
        return getfield(c, s)
    end
    return getproperty(getfield(c, :group), s)
end

# ── add! / remove! ───────────────────────────────────────────────────────

"""
    add!(c::Company, person::Person)

Add a worker to the company.
"""
function add!(c::Company, person::Person)
    sg = c.group.subgroups[1]
    push!(sg.people, person)
    person.subgroups.primary_activity = sg
    return nothing
end

"""
    remove!(c::Company, person::Person)

Remove a worker from the company.
"""
function remove!(c::Company, person::Person)
    sg = c.group.subgroups[1]
    filter!(p -> p.id != person.id, sg.people)
    if person.subgroups.primary_activity === sg
        person.subgroups.primary_activity = nothing
    end
    return nothing
end

# ── Queries ──────────────────────────────────────────────────────────────

"""All workers in the company."""
people(c::Company) = people(c.group)

"""Number of workers."""
n_workers(c::Company) = length(c.group.subgroups[1])

"""True when the company has reached capacity."""
is_full(c::Company) = n_workers(c) >= c.n_workers_max

"""The `SuperArea` this company's area belongs to, or `nothing`."""
function super_area(c::Company)
    a = c.group.area
    a === nothing && return nothing
    return a.super_area
end

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, c::Company)
    sec = c.sector === nothing ? "" : ", sector=\"$(c.sector)\""
    print(io, "Company(id=$(c.group.id)$sec, workers=$(n_workers(c))/$(c.n_workers_max))")
end

# ── Supergroup factory ───────────────────────────────────────────────────

const Companies = Supergroup

"""
    create_companies(companies::Vector{Company}) -> Supergroup

Wrap a vector of `Company` instances in a `Supergroup`.
"""
function create_companies(companies::Vector{Company})
    groups = [c.group for c in companies]
    return Supergroup("companies", groups)
end
