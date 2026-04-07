# ============================================================================
# Household — residence group with age-based subgroups
#
# Included inside `module June`; no sub-module wrapper.
# Subgroups: 1=kids (0–5), 2=young_adults (6–17), 3=adults (18–64),
#            4=old_adults (65+)
# ============================================================================

# ── Struct ───────────────────────────────────────────────────────────────

mutable struct Household
    group::Group
    type::Union{Nothing, String}
    max_size::Int
    quarantine_starting_date::Any   # Union{Nothing, DateTime}
    residents::Vector{Int}          # person IDs of permanent residents
end

# ── Constructor ──────────────────────────────────────────────────────────

"""
    Household(; area=nothing, type=nothing, max_size=12)

Create a household with four age-based subgroups.
"""
function Household(; area=nothing, type=nothing, max_size::Int=12)
    g = Group("household", 4; area=area)
    return Household(g, type, max_size, nothing, Int[])
end

# ── Property delegation ──────────────────────────────────────────────────

function Base.getproperty(h::Household, s::Symbol)
    if s in (:group, :type, :max_size, :quarantine_starting_date, :residents)
        return getfield(h, s)
    end
    return getproperty(getfield(h, :group), s)
end

# ── Age → subgroup mapping ───────────────────────────────────────────────

function _household_subgroup_index(age::Int)
    age < 6   && return 1   # kids
    age < 18  && return 2   # young adults
    age < 65  && return 3   # adults
    return 4                # old adults
end

# ── add! ─────────────────────────────────────────────────────────────────

"""
    add!(h::Household, person::Person; activity::Symbol=:residence)

Add a person to the household.  `:residence` marks them as a permanent
resident; `:leisure` adds them as a visitor.
"""
function add!(h::Household, person::Person; activity::Symbol=:residence)
    idx = _household_subgroup_index(person.age)
    sg = h.group.subgroups[idx]
    push!(sg.people, person)
    if activity == :residence
        person.subgroups.residence = sg
        push!(h.residents, person.id)
    elseif activity == :leisure
        person.subgroups.leisure = sg
    end
    return nothing
end

# ── Queries ──────────────────────────────────────────────────────────────

"""All people currently in the household (residents + visitors)."""
people(h::Household) = people(h.group)

"""Number of permanent residents."""
n_residents(h::Household) = length(h.residents)

"""The `SuperArea` this household's area belongs to, or `nothing`."""
function super_area(h::Household)
    a = h.group.area
    a === nothing && return nothing
    return a.super_area
end

"""True when the household is at capacity."""
is_full(h::Household) = n_people(h.group) >= h.max_size

# ── Quarantine ───────────────────────────────────────────────────────────

"""
    quarantine!(h::Household, date; compliance=1.0)

Start a quarantine for the household.  Each resident obeys with probability
`compliance`.
"""
function quarantine!(h::Household, date; compliance::Float64=1.0)
    h.quarantine_starting_date = date
    for sg in h.group.subgroups
        for p in sg.people
            if rand() < compliance
                p.lockdown_status = "quarantine"
            end
        end
    end
    return nothing
end

"""End the current quarantine."""
function end_quarantine!(h::Household)
    h.quarantine_starting_date = nothing
    for sg in h.group.subgroups
        for p in sg.people
            if p.lockdown_status == "quarantine"
                p.lockdown_status = nothing
            end
        end
    end
    return nothing
end

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, h::Household)
    t = h.type === nothing ? "" : ", type=\"$(h.type)\""
    print(io, "Household(id=$(h.group.id)$t, residents=$(n_residents(h)))")
end

# ── Supergroup factory ───────────────────────────────────────────────────

const Households = Supergroup

"""
    create_households(households::Vector{Household}) -> Supergroup

Wrap a vector of `Household` instances in a `Supergroup`.
"""
function create_households(households::Vector{Household})
    groups = [h.group for h in households]
    return Supergroup("households", groups)
end
