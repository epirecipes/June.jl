"""
    Person

Central agent type for the simulation.  Each person carries demographic
attributes, activity-subgroup assignments, and optional infection / immunity
state.  Mirrors the Python `Person(dataobject)`.
"""

# ── ID generation ────────────────────────────────────────────────────────

const _PERSON_ID_COUNTER = Ref(0)

"""Generate the next unique person ID (1-based, thread-unsafe)."""
function next_person_id!()
    _PERSON_ID_COUNTER[] += 1
    return _PERSON_ID_COUNTER[]
end

"""Reset the person-ID counter to zero (useful for tests)."""
function reset_person_ids!()
    _PERSON_ID_COUNTER[] = 0
end

# ── Struct ───────────────────────────────────────────────────────────────

mutable struct Person
    id::Int
    sex::Char                            # 'm' or 'f'
    age::Int
    ethnicity::Union{Nothing, String}
    area::Any                            # will be Area
    work_super_area::Any                 # will be SuperArea
    sector::Union{Nothing, String}
    sub_sector::Union{Nothing, String}
    lockdown_status::Union{Nothing, String}
    vaccine_trajectory::Any              # will be VaccineTrajectory
    vaccinated::Union{Nothing, Int}
    vaccine_type::Union{Nothing, String}
    comorbidity::Union{Nothing, String}
    mode_of_transport::Any               # will be ModeOfTransport
    busy::Bool
    subgroups::Activities
    infection::Any                       # will be Infection
    immunity::Any                        # will be Immunity
    dead::Bool
end

"""
    Person(; sex='f', age=27, ethnicity=nothing, id=nothing, comorbidity=nothing)

Convenience constructor matching the Python `Person.from_attributes` factory.
Auto-generates a unique ID when `id` is `nothing`.
"""
function Person(;
    sex::Char = 'f',
    age::Int = 27,
    ethnicity::Union{Nothing, String} = nothing,
    id::Union{Nothing, Int} = nothing,
    comorbidity::Union{Nothing, String} = nothing,
)
    pid = id === nothing ? next_person_id!() : id
    return Person(
        pid,
        sex,
        age,
        ethnicity,
        nothing,   # area
        nothing,   # work_super_area
        nothing,   # sector
        nothing,   # sub_sector
        nothing,   # lockdown_status
        nothing,   # vaccine_trajectory
        nothing,   # vaccinated
        nothing,   # vaccine_type
        comorbidity,
        nothing,   # mode_of_transport
        false,     # busy
        Activities(),
        nothing,   # infection
        nothing,   # immunity
        false,     # dead
    )
end

# ── Property-style accessors ─────────────────────────────────────────────

"""True when the person currently carries an infection."""
is_infected(p::Person) = p.infection !== nothing

"""Residence subgroup, or `nothing`."""
residence(p::Person) = p.subgroups.residence

"""Primary-activity subgroup, or `nothing`."""
primary_activity(p::Person) = p.subgroups.primary_activity

"""Medical-facility subgroup, or `nothing`."""
medical_facility(p::Person) = p.subgroups.medical_facility

"""Commute subgroup, or `nothing`."""
commute(p::Person) = p.subgroups.commute

"""Rail-travel subgroup, or `nothing`."""
rail_travel(p::Person) = p.subgroups.rail_travel

"""Leisure subgroup, or `nothing`."""
leisure(p::Person) = p.subgroups.leisure

"""Current symptoms (from infection), or `nothing` if not infected."""
function symptoms(p::Person)
    p.infection === nothing && return nothing
    return p.infection.symptoms
end

"""True when the person is assigned to a hospital patient subgroup."""
function is_hospitalised(p::Person)
    mf = p.subgroups.medical_facility
    mf === nothing && return false
    try
        grp = mf.group
        return hasproperty(grp, :spec) && grp.spec == "hospital"
    catch
        return false
    end
end

"""True when the person is in an ICU subgroup."""
function is_intensive_care(p::Person)
    mf = p.subgroups.medical_facility
    mf === nothing && return false
    try
        grp = mf.group
        return hasproperty(grp, :spec) && grp.spec == "hospital" &&
               hasproperty(mf, :subgroup_type) && mf.subgroup_type == grp.SubgroupType.icu_patients
    catch
        return false
    end
end

"""True when the person can participate in daily activities."""
function is_available(p::Person)
    return !p.dead && p.subgroups.medical_facility === nothing && !p.busy
end

"""The `SuperArea` the person lives in, or `nothing`."""
function super_area(p::Person)
    p.area === nothing && return nothing
    try
        return p.area.super_area
    catch
        return nothing
    end
end

"""The `Region` the person lives in, or `nothing`."""
function region(p::Person)
    sa = super_area(p)
    sa === nothing && return nothing
    try
        return sa.region
    catch
        return nothing
    end
end

"""Housemates (other people in the same residence group), or empty vector."""
function housemates(p::Person)
    res = residence(p)
    res === nothing && return Person[]
    try
        grp = res.group
        if hasproperty(grp, :spec) && grp.spec == "care_home"
            return Person[]
        end
        return grp.residents
    catch
        return Person[]
    end
end

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, p::Person)
    status = p.dead ? "dead" : (is_infected(p) ? "infected" : "healthy")
    print(io, "Person(id=$(p.id), sex=$(p.sex), age=$(p.age), $status)")
end
