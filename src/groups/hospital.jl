# ============================================================================
# Hospital — medical facility with workers, ward patients, and ICU patients
#
# Included inside `module June`; no sub-module wrapper.
# Subgroups: 1=workers, 2=patients (ward), 3=icu_patients
# ============================================================================

# ── Struct ───────────────────────────────────────────────────────────────

mutable struct Hospital
    group::Group
    ward_ids::Set{Int}                  # person IDs in ward
    icu_ids::Set{Int}                   # person IDs in ICU
    trust_code::Union{Nothing, String}
end

# ── Constructor ──────────────────────────────────────────────────────────

"""
    Hospital(; trust_code=nothing, area=nothing)

Create a hospital with three subgroups: workers, ward patients, ICU patients.
"""
function Hospital(; trust_code=nothing, area=nothing)
    g = Group("hospital", 3; area=area)
    return Hospital(g, Set{Int}(), Set{Int}(), trust_code)
end

# ── Property delegation ──────────────────────────────────────────────────

function Base.getproperty(h::Hospital, s::Symbol)
    if s in (:group, :ward_ids, :icu_ids, :trust_code)
        return getfield(h, s)
    end
    return getproperty(getfield(h, :group), s)
end

# ── Subgroup accessors ───────────────────────────────────────────────────

"""Workers subgroup."""
workers(h::Hospital) = h.group.subgroups[1]

"""Ward patients subgroup."""
ward(h::Hospital) = h.group.subgroups[2]

"""ICU patients subgroup."""
icu(h::Hospital) = h.group.subgroups[3]

# ── add! for workers ─────────────────────────────────────────────────────

"""
    add!(h::Hospital, person::Person)

Add a worker (staff member) to the hospital.
"""
function add!(h::Hospital, person::Person)
    sg = h.group.subgroups[1]
    push!(sg.people, person)
    person.subgroups.primary_activity = sg
    return nothing
end

# ── Ward / ICU management ────────────────────────────────────────────────

"""
    add_to_ward!(h::Hospital, person::Person)

Admit a person to the general ward (subgroup 2).
"""
function add_to_ward!(h::Hospital, person::Person)
    sg = h.group.subgroups[2]
    push!(sg.people, person)
    push!(h.ward_ids, person.id)
    person.subgroups.medical_facility = sg
    return nothing
end

"""
    add_to_icu!(h::Hospital, person::Person)

Admit a person to the ICU (subgroup 3).
"""
function add_to_icu!(h::Hospital, person::Person)
    sg = h.group.subgroups[3]
    push!(sg.people, person)
    push!(h.icu_ids, person.id)
    person.subgroups.medical_facility = sg
    return nothing
end

"""
    allocate_patient!(h::Hospital, person::Person; icu=false)

Route a patient to ward or ICU.  When `icu` is not specified, patients whose
infection symptoms tag indicates critical illness go to ICU.
"""
function allocate_patient!(h::Hospital, person::Person; icu::Bool=false)
    if icu
        add_to_icu!(h, person)
    else
        # heuristic: check for intensive_care symptom tag
        sym = person.infection !== nothing ? person.infection.symptoms : nothing
        if sym !== nothing && hasproperty(sym, :tag) && sym.tag == :intensive_care
            add_to_icu!(h, person)
        else
            add_to_ward!(h, person)
        end
    end
    return nothing
end

"""
    release_patient!(h::Hospital, person::Person)

Remove a patient from ward or ICU and clear their medical_facility slot.
"""
function release_patient!(h::Hospital, person::Person)
    pid = person.id
    if pid in h.ward_ids
        filter!(p -> p.id != pid, h.group.subgroups[2].people)
        delete!(h.ward_ids, pid)
    end
    if pid in h.icu_ids
        filter!(p -> p.id != pid, h.group.subgroups[3].people)
        delete!(h.icu_ids, pid)
    end
    person.subgroups.medical_facility = nothing
    return nothing
end

# ── Queries ──────────────────────────────────────────────────────────────

"""All people in the hospital (workers + patients)."""
people(h::Hospital) = people(h.group)

"""Number of ward patients."""
n_ward_patients(h::Hospital) = length(h.ward_ids)

"""Number of ICU patients."""
n_icu_patients(h::Hospital) = length(h.icu_ids)

"""Number of workers."""
n_workers(h::Hospital) = length(h.group.subgroups[1])

"""Total number of patients (ward + ICU)."""
n_patients(h::Hospital) = n_ward_patients(h) + n_icu_patients(h)

"""The `SuperArea` this hospital's area belongs to, or `nothing`."""
function super_area(h::Hospital)
    a = h.group.area
    a === nothing && return nothing
    return a.super_area
end

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, h::Hospital)
    tc = h.trust_code === nothing ? "" : ", trust=\"$(h.trust_code)\""
    print(io, "Hospital(id=$(h.group.id)$tc, workers=$(n_workers(h)), ",
          "ward=$(n_ward_patients(h)), icu=$(n_icu_patients(h)))")
end

# ── Supergroup factory ───────────────────────────────────────────────────

const Hospitals = Supergroup

"""
    create_hospitals(hospitals::Vector{Hospital}) -> Supergroup

Wrap a vector of `Hospital` instances in a `Supergroup`.
"""
function create_hospitals(hospitals::Vector{Hospital})
    groups = [h.group for h in hospitals]
    return Supergroup("hospitals", groups)
end
