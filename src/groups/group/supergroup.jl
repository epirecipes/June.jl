# ============================================================================
# Supergroup — collection of groups of the same spec
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

"""
    Supergroup

A collection of `Group` instances of the same spec (e.g. all households).
Provides O(1) lookup by group ID via an ordered dictionary.
"""
mutable struct Supergroup
    group_type::String
    spec::String
    members::Vector{Group}
    members_by_id::OrderedDict{Int, Group}
end

# ── Constructor ──────────────────────────────────────────────────────────

function Supergroup(spec::String, members::Vector{Group} = Group[])
    members_by_id = OrderedDict{Int, Group}(g.id => g for g in members)
    return Supergroup(spec, spec, members, members_by_id)
end

# ── Lookup ───────────────────────────────────────────────────────────────

"""Look up a group by its unique ID."""
get_from_id(sg::Supergroup, id::Int) = sg.members_by_id[id]

"""Return the IDs of all member groups."""
member_ids(sg::Supergroup) = collect(keys(sg.members_by_id))

# ── Mutation ─────────────────────────────────────────────────────────────

"""Add a group to this supergroup."""
function add!(sg::Supergroup, group::Group)
    push!(sg.members, group)
    sg.members_by_id[group.id] = group
    return sg
end

"""Clear the ID lookup dictionary (members vector is preserved)."""
function clear!(sg::Supergroup)
    empty!(sg.members_by_id)
    return sg
end

# ── Collection interface ─────────────────────────────────────────────────

Base.length(sg::Supergroup)            = length(sg.members)
Base.iterate(sg::Supergroup)           = iterate(sg.members)
Base.iterate(sg::Supergroup, state)    = iterate(sg.members, state)
Base.getindex(sg::Supergroup, i::Int)  = sg.members[i]
Base.lastindex(sg::Supergroup)         = lastindex(sg.members)
Base.isempty(sg::Supergroup)           = isempty(sg.members)
Base.eltype(::Type{Supergroup})        = Group
Base.push!(sg::Supergroup, g::Group)   = add!(sg, g)

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, sg::Supergroup)
    n = length(sg)
    print(io, "Supergroup(spec=\"$(sg.spec)\", members=$n)")
end
