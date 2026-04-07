# ============================================================================
# Group — concrete base group with spec label and subgroups
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

"""
    Group <: AbstractGroup

A concrete group that holds a fixed number of `Subgroup` slots.
Each group has a unique per-spec ID, a spec string (e.g. `"household"`),
and an optional geographic area reference.
"""
mutable struct Group <: AbstractGroup
    id::Int
    spec::String
    subgroups::Vector{Subgroup}
    area::Any               # optional Area / SuperArea
    external::Bool
end

# ── Per-spec ID counters ─────────────────────────────────────────────────

const _GROUP_ID_COUNTERS = Dict{String, Ref{Int}}()

"""Return the next unique ID for groups of the given spec."""
function next_group_id!(spec::String)
    if !haskey(_GROUP_ID_COUNTERS, spec)
        _GROUP_ID_COUNTERS[spec] = Ref(0)
    end
    _GROUP_ID_COUNTERS[spec][] += 1
    return _GROUP_ID_COUNTERS[spec][]
end

"""
    reset_group_ids!(spec="")

Reset ID counter(s).  If `spec` is empty, reset all counters.
"""
function reset_group_ids!(spec::String = "")
    if isempty(spec)
        empty!(_GROUP_ID_COUNTERS)
    else
        _GROUP_ID_COUNTERS[spec] = Ref(0)
    end
end

# ── Constructor ──────────────────────────────────────────────────────────

"""
    Group(spec, n_subgroups; area=nothing, external=false)

Create a new group with `n_subgroups` empty subgroup slots.
"""
function Group(spec::String, n_subgroups::Int; area = nothing, external = false)
    id = next_group_id!(spec)
    subgroups = [Subgroup(nothing, i) for i in 1:n_subgroups]
    g = Group(id, spec, subgroups, area, external)
    for sg in g.subgroups
        sg.group = g
    end
    return g
end

# ── AbstractGroup interface ──────────────────────────────────────────────

"""Return all people across every subgroup."""
function people(g::Group)
    result = Person[]
    for sg in g.subgroups
        append!(result, sg.people)
    end
    return result
end

# ── Mutation ─────────────────────────────────────────────────────────────

"""Add a person to the subgroup at index `subgroup_idx`."""
function add!(g::Group, person::Person, subgroup_idx::Int)
    add!(g.subgroups[subgroup_idx], person)
    return g
end

"""Remove a person from whichever subgroup contains them."""
function remove!(g::Group, person::Person)
    for sg in g.subgroups
        if person in sg
            remove!(sg, person)
            return g
        end
    end
    return g
end

"""Clear all subgroups."""
function clear!(g::Group)
    for sg in g.subgroups
        clear!(sg)
    end
    return g
end

# ── Collection interface ─────────────────────────────────────────────────

Base.length(g::Group) = sum(length(sg) for sg in g.subgroups; init = 0)

Base.getindex(g::Group, i::Int) = g.subgroups[i]

function Base.iterate(g::Group)
    isempty(g.subgroups) && return nothing
    return iterate(g.subgroups)
end
Base.iterate(g::Group, state) = iterate(g.subgroups, state)

# ── Aliases for backward compatibility ───────────────────────────────────

"""Total number of people in the group."""
n_people(g::Group) = length(g)

"""Size of a specific subgroup (1-based index)."""
subgroup_size(g::Group, idx::Int) = length(g.subgroups[idx])

# ── Spec helpers ─────────────────────────────────────────────────────────

"""
    get_spec(name::String) → String

Convert a CamelCase class name to a snake_case spec string.
E.g. `"CareHome" → "care_home"`, `"Household" → "household"`.
"""
function get_spec(name::String)
    s = replace(name, r"([a-z])([A-Z])" => s"\1_\2")
    return lowercase(s)
end

# ── Query helpers ────────────────────────────────────────────────────────

"""True when the group should be time-stepped for infection."""
function must_timestep(g::Group)
    has_sus = false
    has_inf = false
    for sg in g.subgroups
        for p in sg.people
            if is_infected(p)
                has_inf = true
            elseif !p.dead
                has_sus = true
            end
            has_sus && has_inf && return true
        end
    end
    return false
end

"""Human-readable name: spec_00042."""
function name(g::Group)
    return "$(g.spec)_$(lpad(g.id, 5, '0'))"
end

# ── Non-allocating people iterator ───────────────────────────────────────

"""Iterator over all people across every subgroup — zero allocations."""
struct GroupPeopleIterator
    group::Group
end

Base.IteratorSize(::Type{GroupPeopleIterator}) = Base.SizeUnknown()
Base.eltype(::Type{GroupPeopleIterator}) = Person

function Base.iterate(gpi::GroupPeopleIterator)
    g = gpi.group
    for (si, sg) in enumerate(g.subgroups)
        if !isempty(sg.people)
            return (sg.people[1], (si, 1))
        end
    end
    return nothing
end

function Base.iterate(gpi::GroupPeopleIterator, state::Tuple{Int,Int})
    g = gpi.group
    si, pi = state
    pi += 1
    while si <= length(g.subgroups)
        sg = g.subgroups[si]
        if pi <= length(sg.people)
            return (sg.people[pi], (si, pi))
        end
        si += 1
        pi = 1
    end
    return nothing
end

"""Non-allocating iterator over all people in a group."""
eachperson(g::Group) = GroupPeopleIterator(g)

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, g::Group)
    n = length(g)
    nsub = length(g.subgroups)
    print(io, "Group(id=$(g.id), spec=\"$(g.spec)\", subgroups=$nsub, people=$n)")
end
