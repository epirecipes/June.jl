# ============================================================================
# School — education group with teacher + year-based student subgroups
#
# Included inside `module June`; no sub-module wrapper.
# Subgroups: 1=teachers, 2..n+1=student year groups (by age)
# ============================================================================

# ── Struct ───────────────────────────────────────────────────────────────

mutable struct School
    group::Group
    n_pupils_max::Int
    age_min::Int
    age_max::Int
    sector::String              # "primary", "secondary", "both"
    n_classrooms::Int
    years::Dict{Int,Int}        # age → subgroup index
end

# ── Constructor ──────────────────────────────────────────────────────────

"""
    School(coordinates, n_pupils_max, age_min, age_max, sector; area=nothing)

Create a school with one teacher subgroup and one subgroup per year.
"""
function School(coordinates, n_pupils_max::Int, age_min::Int, age_max::Int,
                sector::String; area=nothing)
    n_years = age_max - age_min + 1
    n_subgroups = 1 + n_years   # index 1 = teachers
    g = Group("school", n_subgroups; area=area)
    years = Dict(age => (age - age_min + 2) for age in age_min:age_max)
    return School(g, n_pupils_max, age_min, age_max, sector, 0, years)
end

# ── Property delegation ──────────────────────────────────────────────────

function Base.getproperty(s::School, sym::Symbol)
    if sym in (:group, :n_pupils_max, :age_min, :age_max, :sector,
               :n_classrooms, :years)
        return getfield(s, sym)
    end
    return getproperty(getfield(s, :group), sym)
end

# ── add! ─────────────────────────────────────────────────────────────────

"""
    add!(s::School, person::Person)

Add a person to the school.  Students go to the year subgroup matching their
age; anyone older than `age_max` is added as a teacher (subgroup 1).
"""
function add!(s::School, person::Person)
    if person.age > s.age_max || person.age < s.age_min
        # teacher
        sg = s.group.subgroups[1]
        push!(sg.people, person)
        person.subgroups.primary_activity = sg
    else
        idx = get(s.years, person.age, nothing)
        if idx !== nothing
            sg = s.group.subgroups[idx]
            push!(sg.people, person)
            person.subgroups.primary_activity = sg
        end
    end
    return nothing
end

# ── Queries ──────────────────────────────────────────────────────────────

"""All people in the school."""
people(s::School) = people(s.group)

"""Number of pupils (all subgroups except teachers)."""
function n_pupils(s::School)
    return sum(length(s.group.subgroups[i]) for i in 2:length(s.group.subgroups); init=0)
end

"""Number of teachers (subgroup 1)."""
n_teachers(s::School) = length(s.group.subgroups[1])

"""True when the school has reached its pupil capacity."""
is_full(s::School) = n_pupils(s) >= s.n_pupils_max

"""The `SuperArea` this school's area belongs to, or `nothing`."""
function super_area(s::School)
    a = s.group.area
    a === nothing && return nothing
    return a.super_area
end

# ── Classroom management ─────────────────────────────────────────────────

"""
    limit_classroom_sizes!(s::School; max_size=30)

Stub for splitting year subgroups that exceed `max_size` into classrooms.
Currently records how many classrooms would be needed.
"""
function limit_classroom_sizes!(s::School; max_size::Int=30)
    total = 0
    for i in 2:length(s.group.subgroups)
        n = length(s.group.subgroups[i])
        total += max(1, ceil(Int, n / max_size))
    end
    s.n_classrooms = total
    return total
end

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, s::School)
    print(io, "School(id=$(s.group.id), sector=\"$(s.sector)\", ",
          "pupils=$(n_pupils(s))/$(s.n_pupils_max), teachers=$(n_teachers(s)))")
end

# ── Supergroup factory ───────────────────────────────────────────────────

const Schools = Supergroup

"""
    create_schools(schools::Vector{School}) -> Supergroup

Wrap a vector of `School` instances in a `Supergroup`.
"""
function create_schools(schools::Vector{School})
    groups = [s.group for s in schools]
    return Supergroup("schools", groups)
end
