# ---------------------------------------------------------------------------
# World — top-level container for the entire simulation world
# ---------------------------------------------------------------------------

const POSSIBLE_GROUPS = [
    "households", "care_homes", "schools", "hospitals",
    "companies", "universities", "pubs", "groceries", "cinemas"
]

mutable struct World
    areas::Union{Nothing, Areas}
    super_areas::Union{Nothing, SuperAreas}
    regions::Union{Nothing, Regions}
    people::Union{Nothing, Population}
    households::Any
    care_homes::Any
    schools::Any
    companies::Any
    hospitals::Any
    pubs::Any
    groceries::Any
    cinemas::Any
    cemeteries::Union{Nothing, Cemeteries}
    universities::Any
    cities::Any
    stations::Any
end

function World()
    return World(nothing, nothing, nothing, nothing,
                 nothing, nothing, nothing, nothing, nothing,
                 nothing, nothing, nothing, nothing, nothing,
                 nothing, nothing)
end

# ---------------------------------------------------------------------------
# distribute_people! — run all distributors in order
# ---------------------------------------------------------------------------

"""
    distribute_people!(world::World; include_households=true)

Run distributors in the correct order to populate all groups with people.
"""
function distribute_people!(world::World; include_households::Bool=true)
    # 1. WorkerDistributor — classify workers by sector
    if !isnothing(world.companies) || !isnothing(world.hospitals) ||
       !isnothing(world.schools) || !isnothing(world.care_homes)
        wd = worker_distributor_for_super_areas(;
            area_names=[a.name for a in world.areas.members])
        distribute_workers!(wd;
            areas=world.areas, super_areas=world.super_areas, population=world.people)
    end

    # 2. CareHomeDistributor — move elderly into care homes
    if !isnothing(world.care_homes)
        chd = care_home_distributor_from_file()
        populate_care_homes!(chd, world.super_areas)
    end

    # 3. HouseholdDistributor
    if include_households
        hd = household_distributor_from_file()
        hs = distribute_people_and_households!(hd, world.areas)
        if isnothing(world.households)
            world.households = create_households(hs)
        else
            for h in hs
                push!(world.households, h.group)
            end
        end
    end

    # 4. SchoolDistributor
    if !isnothing(world.schools)
        sd = SchoolDistributor(world.schools)
        distribute_kids_to_school!(sd, world.areas)
        distribute_teachers_to_schools!(sd, world.super_areas)
    end

    # 5. UniversityDistributor
    if !isnothing(world.universities)
        ud = UniversityDistributor(world.universities)
        distribute_students_to_universities!(ud;
            areas=world.areas, people=world.people)
    end

    # 6. CareHome workers (after universities so students aren't taken)
    if !isnothing(world.care_homes)
        chd = care_home_distributor_from_file()
        distribute_workers_to_care_homes!(chd, world.super_areas)
    end

    # 7. HospitalDistributor
    if !isnothing(world.hospitals)
        hd_hosp = hospital_distributor_from_file(world.hospitals)
        assign_closest_hospitals!(hd_hosp, world.super_areas)
        distribute_medics!(hd_hosp, world.super_areas)
    end

    # 8. CompanyDistributor — last, absorbs remaining workers
    if !isnothing(world.companies)
        cd = CompanyDistributor()
        distribute_adults_to_companies!(cd, world.super_areas)
    end
end

# ---------------------------------------------------------------------------
# Iteration — iterate over all supergroups
# ---------------------------------------------------------------------------

function _supergroup_fields()
    return (:households, :care_homes, :schools, :hospitals, :companies,
            :universities, :pubs, :groceries, :cinemas, :cemeteries)
end

function Base.iterate(w::World)
    return _iterate_world(w, 1)
end

function Base.iterate(w::World, state::Int)
    return _iterate_world(w, state)
end

function _iterate_world(w::World, idx::Int)
    fields = _supergroup_fields()
    while idx <= length(fields)
        val = getfield(w, fields[idx])
        if !isnothing(val)
            return (val, idx + 1)
        end
        idx += 1
    end
    return nothing
end

# ---------------------------------------------------------------------------
# generate_world_from_geography
# ---------------------------------------------------------------------------

"""
    generate_world_from_geography(geography; demography=nothing,
        include_households=true, ethnicity=true, comorbidity=true) -> World

Build a full simulation world from a `Geography` object.
"""
function generate_world_from_geography(geography::Geography;
                                       demography=nothing,
                                       include_households::Bool=true,
                                       ethnicity::Bool=true,
                                       comorbidity::Bool=true)
    world = World()

    if isnothing(demography)
        area_names = [a.name for a in geography.areas.members]
        demography = demography_for_areas(area_names)
    end

    world.areas       = geography.areas
    world.super_areas = geography.super_areas
    world.regions     = geography.regions

    # Populate areas with people
    world.people = Population()
    for area in world.areas.members
        pop = populate!(demography, area.name;
                        ethnicity=ethnicity, comorbidity=comorbidity)
        for person in pop.people
            add!(area, person)
            push!(world.people, person)
        end
    end

    # Copy groups from geography
    for group_name in POSSIBLE_GROUPS
        sym = Symbol(group_name)
        geo_group = getfield(geography, sym)
        if !isnothing(geo_group)
            setfield!(world, sym, geo_group)
        end
    end

    # Distribute people to groups
    distribute_people!(world; include_households=include_households)
    world.cemeteries = Cemeteries()
    return world
end
