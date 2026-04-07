# ============================================================================
# CareHome — residential care with workers, residents, and visitors
#
# Included inside `module June`; no sub-module wrapper.
# Subgroups: 1=workers, 2=residents, 3=visitors
# ============================================================================

# ── Struct ───────────────────────────────────────────────────────────────

mutable struct CareHome
    group::Group
    n_residents::Int
    n_workers::Int
    quarantine_starting_date::Any   # Union{Nothing, DateTime}
end

# ── Constructor ──────────────────────────────────────────────────────────

"""
    CareHome(; area=nothing)

Create a care home with three subgroups: workers, residents, visitors.
"""
function CareHome(; area=nothing)
    g = Group("care_home", 3; area=area)
    return CareHome(g, 0, 0, nothing)
end

# ── Property delegation ──────────────────────────────────────────────────

function Base.getproperty(ch::CareHome, s::Symbol)
    if s in (:group, :n_residents, :n_workers, :quarantine_starting_date)
        return getfield(ch, s)
    end
    return getproperty(getfield(ch, :group), s)
end

# ── add! ─────────────────────────────────────────────────────────────────

"""
    add!(ch::CareHome, person::Person; activity::Symbol=:residence)

Add a person to the care home.

- `:primary_activity` — add as a worker (subgroup 1)
- `:residence` — add as a resident (subgroup 2)
- `:leisure` — add as a visitor (subgroup 3)
"""
function add!(ch::CareHome, person::Person; activity::Symbol=:residence)
    if activity == :primary_activity
        sg = ch.group.subgroups[1]
        push!(sg.people, person)
        person.subgroups.primary_activity = sg
        ch.n_workers += 1
    elseif activity == :residence
        sg = ch.group.subgroups[2]
        push!(sg.people, person)
        person.subgroups.residence = sg
        ch.n_residents += 1
    elseif activity == :leisure
        sg = ch.group.subgroups[3]
        push!(sg.people, person)
        person.subgroups.leisure = sg
    end
    return nothing
end

"""
    remove!(ch::CareHome, person::Person; activity::Symbol=:residence)

Remove a person from the care home.
"""
function remove!(ch::CareHome, person::Person; activity::Symbol=:residence)
    if activity == :primary_activity
        filter!(p -> p.id != person.id, ch.group.subgroups[1].people)
        person.subgroups.primary_activity = nothing
        ch.n_workers = max(0, ch.n_workers - 1)
    elseif activity == :residence
        filter!(p -> p.id != person.id, ch.group.subgroups[2].people)
        person.subgroups.residence = nothing
        ch.n_residents = max(0, ch.n_residents - 1)
    elseif activity == :leisure
        filter!(p -> p.id != person.id, ch.group.subgroups[3].people)
        person.subgroups.leisure = nothing
    end
    return nothing
end

# ── Queries ──────────────────────────────────────────────────────────────

"""All people in the care home."""
people(ch::CareHome) = people(ch.group)

"""The `SuperArea` this care home's area belongs to, or `nothing`."""
function super_area(ch::CareHome)
    a = ch.group.area
    a === nothing && return nothing
    return a.super_area
end

# ── Quarantine ───────────────────────────────────────────────────────────

"""
    quarantine!(ch::CareHome, date; compliance=1.0)

Quarantine the care home.  Each person obeys with probability `compliance`.
"""
function quarantine!(ch::CareHome, date; compliance::Float64=1.0)
    ch.quarantine_starting_date = date
    for sg in ch.group.subgroups
        for p in sg.people
            if rand() < compliance
                p.lockdown_status = "quarantine"
            end
        end
    end
    return nothing
end

"""End the care home quarantine."""
function end_quarantine!(ch::CareHome)
    ch.quarantine_starting_date = nothing
    for sg in ch.group.subgroups
        for p in sg.people
            if p.lockdown_status == "quarantine"
                p.lockdown_status = nothing
            end
        end
    end
    return nothing
end

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, ch::CareHome)
    print(io, "CareHome(id=$(ch.group.id), residents=$(ch.n_residents), ",
          "workers=$(ch.n_workers))")
end

# ── Supergroup factory ───────────────────────────────────────────────────

const CareHomes = Supergroup

"""
    create_care_homes(care_homes::Vector{CareHome}) -> Supergroup

Wrap a vector of `CareHome` instances in a `Supergroup`.
"""
function create_care_homes(care_homes::Vector{CareHome})
    groups = [ch.group for ch in care_homes]
    return Supergroup("care_homes", groups)
end
