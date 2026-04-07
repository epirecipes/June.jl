# ============================================================================
# University — higher education group with year-based student subgroups
#
# Included inside `module June`; no sub-module wrapper.
# Subgroups: 1=staff, 2..n_years+1=student year groups
# ============================================================================

# ── Struct ───────────────────────────────────────────────────────────────

mutable struct University
    group::Group
    n_students_max::Int
    n_years::Int
    ukprn::Union{Nothing, String}   # UK Provider Reference Number
end

# ── Constructor ──────────────────────────────────────────────────────────

"""
    University(; n_students_max=0, n_years=3, ukprn=nothing, area=nothing)

Create a university with one staff subgroup and `n_years` student subgroups.
"""
function University(; n_students_max::Int=0, n_years::Int=3,
                      ukprn=nothing, area=nothing)
    n_subgroups = 1 + n_years   # index 1 = staff
    g = Group("university", n_subgroups; area=area)
    return University(g, n_students_max, n_years, ukprn)
end

# ── Property delegation ──────────────────────────────────────────────────

function Base.getproperty(u::University, s::Symbol)
    if s in (:group, :n_students_max, :n_years, :ukprn)
        return getfield(u, s)
    end
    return getproperty(getfield(u, :group), s)
end

# ── Age → year mapping ───────────────────────────────────────────────────

"""Map a student age to a 1-based year index (subgroup offset by 1 for staff)."""
function _university_year_index(u::University, age::Int)
    # Assume typical university entry at 18
    year = age - 18 + 1
    year = clamp(year, 1, u.n_years)
    return year + 1   # +1 because subgroup 1 = staff
end

# ── add! ─────────────────────────────────────────────────────────────────

"""
    add!(u::University, person::Person; activity::Symbol=:primary_activity)

Add a person to the university.  Staff are added with
`activity=:primary_activity` when their age is above typical student range;
students are placed in year subgroups by age.
"""
function add!(u::University, person::Person; activity::Symbol=:primary_activity)
    if person.age >= 18 + u.n_years
        # staff
        sg = u.group.subgroups[1]
        push!(sg.people, person)
        person.subgroups.primary_activity = sg
    else
        idx = _university_year_index(u, person.age)
        sg = u.group.subgroups[idx]
        push!(sg.people, person)
        person.subgroups.primary_activity = sg
    end
    return nothing
end

# ── Queries ──────────────────────────────────────────────────────────────

"""All people in the university."""
people(u::University) = people(u.group)

"""Number of students (all subgroups except staff)."""
function n_students(u::University)
    return sum(length(u.group.subgroups[i]) for i in 2:length(u.group.subgroups); init=0)
end

"""Number of staff (subgroup 1)."""
n_staff(u::University) = length(u.group.subgroups[1])

"""True when the university has reached student capacity."""
is_full(u::University) = n_students(u) >= u.n_students_max

"""The `SuperArea` this university's area belongs to, or `nothing`."""
function super_area(u::University)
    a = u.group.area
    a === nothing && return nothing
    return a.super_area
end

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, u::University)
    code = u.ukprn === nothing ? "" : ", ukprn=\"$(u.ukprn)\""
    print(io, "University(id=$(u.group.id)$code, students=$(n_students(u))/$(u.n_students_max), ",
          "staff=$(n_staff(u)))")
end

# ── Supergroup factory ───────────────────────────────────────────────────

const Universities = Supergroup

"""
    create_universities(universities::Vector{University}) -> Supergroup

Wrap a vector of `University` instances in a `Supergroup`.
"""
function create_universities(universities::Vector{University})
    groups = [u.group for u in universities]
    return Supergroup("universities", groups)
end
