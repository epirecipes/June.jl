# ============================================================================
# Subgroup — a single mixing bucket within a Group
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

"""
    Subgroup <: AbstractGroup

A partition within a `Group` (e.g. an age cohort in a household).
Holds a flat vector of `Person` references and a back-pointer to the
parent `Group`.
"""
mutable struct Subgroup <: AbstractGroup
    group::Any           # parent Group (typed as Any to break circular ref)
    subgroup_type::Int   # 1-based index within the parent group
    people::Vector{Person}
end

Subgroup(group, subgroup_type::Int) = Subgroup(group, subgroup_type, Person[])

# ── AbstractGroup interface ──────────────────────────────────────────────

people(sg::Subgroup) = sg.people

# ── Spec delegation ──────────────────────────────────────────────────────

"""Spec string inherited from the parent group."""
function spec(sg::Subgroup)
    sg.group === nothing && return "unknown"
    return sg.group.spec
end

# ── Mutation ─────────────────────────────────────────────────────────────

"""Add a person to this subgroup and mark them as busy."""
function add!(sg::Subgroup, person::Person)
    push!(sg.people, person)
    person.busy = true
    return sg
end

"""Remove a person from this subgroup and mark them as not busy."""
function remove!(sg::Subgroup, person::Person)
    idx = findfirst(p -> p === person, sg.people)
    if idx !== nothing
        deleteat!(sg.people, idx)
        person.busy = false
    end
    return sg
end

"""Remove all people from this subgroup."""
function clear!(sg::Subgroup)
    empty!(sg.people)
    return sg
end

# ── Collection interface ─────────────────────────────────────────────────

Base.length(sg::Subgroup)             = length(sg.people)
Base.iterate(sg::Subgroup)            = iterate(sg.people)
Base.iterate(sg::Subgroup, state)     = iterate(sg.people, state)
Base.in(person::Person, sg::Subgroup) = any(p -> p === person, sg.people)
Base.isempty(sg::Subgroup)            = isempty(sg.people)

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, sg::Subgroup)
    s = spec(sg)
    print(io, "Subgroup(spec=$s, type=$(sg.subgroup_type), n=$(length(sg)))")
end
