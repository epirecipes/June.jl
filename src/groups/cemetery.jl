# ============================================================================
# Cemetery — final resting place for dead agents
#
# Included inside `module June`; no sub-module wrapper.
# Subgroups: 1=dead
# ============================================================================

# ── Struct ───────────────────────────────────────────────────────────────

mutable struct Cemetery
    group::Group
end

# ── Constructor ──────────────────────────────────────────────────────────

"""
    Cemetery()

Create a cemetery with a single subgroup for the dead.
"""
function Cemetery()
    return Cemetery(Group("cemetery", 1))
end

# ── Property delegation ──────────────────────────────────────────────────

function Base.getproperty(c::Cemetery, s::Symbol)
    if s == :group
        return getfield(c, :group)
    end
    return getproperty(getfield(c, :group), s)
end

# ── add! ─────────────────────────────────────────────────────────────────

"""
    add!(c::Cemetery, person::Person)

Bury a person: mark them dead and add to the cemetery.
"""
function add!(c::Cemetery, person::Person)
    push!(c.group.subgroups[1].people, person)
    person.dead = true
    return nothing
end

# ── Queries ──────────────────────────────────────────────────────────────

"""All people buried in this cemetery."""
people(c::Cemetery) = people(c.group)

"""Number of buried people."""
n_dead(c::Cemetery) = length(c.group.subgroups[1])

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, c::Cemetery)
    print(io, "Cemetery(id=$(c.group.id), dead=$(n_dead(c)))")
end

# ── Cemeteries supergroup ────────────────────────────────────────────────

mutable struct Cemeteries
    members::Vector{Cemetery}
end

"""
    Cemeteries()

Create a `Cemeteries` collection with one default cemetery.
"""
function Cemeteries()
    return Cemeteries([Cemetery()])
end

"""Add a person to the first available cemetery."""
function add!(cs::Cemeteries, person::Person)
    add!(cs.members[1], person)
    return nothing
end

Base.length(cs::Cemeteries) = length(cs.members)
Base.iterate(cs::Cemeteries, state...) = iterate(cs.members, state...)
Base.getindex(cs::Cemeteries, i) = cs.members[i]

function Base.show(io::IO, cs::Cemeteries)
    total = sum(n_dead(c) for c in cs.members; init=0)
    print(io, "Cemeteries(n=$(length(cs.members)), total_dead=$total)")
end
