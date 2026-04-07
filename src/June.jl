module June

using CSV
using DataFrames
using Dates
using Distributions
using HDF5
using LinearAlgebra
using NearestNeighbors
using OrderedCollections
using Random
using SpecialFunctions
using Statistics
using StatsBase
using YAML

# ---------------------------------------------------------------------------
# Paths & configuration
# ---------------------------------------------------------------------------
include("paths.jl")

# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------
include("exceptions.jl")

# ---------------------------------------------------------------------------
# Core types (enums, person, activities, immunity stubs)
# ---------------------------------------------------------------------------
include("demography/symptom_tag.jl")
include("demography/activities.jl")
include("demography/person.jl")
include("demography/population.jl")

# ---------------------------------------------------------------------------
# Geography
# ---------------------------------------------------------------------------
include("geography/geography.jl")

# ---------------------------------------------------------------------------
# Groups — abstract hierarchy
# ---------------------------------------------------------------------------
include("groups/group/abstract.jl")
include("groups/group/subgroup.jl")
include("groups/group/make_subgroups.jl")
include("groups/group/group.jl")
include("groups/group/supergroup.jl")
include("groups/group/external.jl")
include("groups/group/interactive.jl")

# ---------------------------------------------------------------------------
# Concrete groups
# ---------------------------------------------------------------------------
include("groups/household.jl")
include("groups/school.jl")
include("groups/company.jl")
include("groups/hospital.jl")
include("groups/care_home.jl")
include("groups/university.jl")
include("groups/cemetery.jl")
include("groups/leisure/social_venue.jl")
include("groups/leisure/social_venue_distributor.jl")
include("groups/leisure/pub.jl")
include("groups/leisure/cinema.jl")
include("groups/leisure/grocery.jl")
include("groups/leisure/gym.jl")
include("groups/leisure/residence_visits.jl")
include("groups/leisure/leisure.jl")
include("groups/travel/mode_of_transport.jl")
include("groups/travel/transport.jl")
include("groups/travel/travel.jl")

# ---------------------------------------------------------------------------
# Epidemiology
# ---------------------------------------------------------------------------
include("epidemiology/infection/transmission.jl")
include("epidemiology/infection/symptoms.jl")
include("epidemiology/infection/infection.jl")
include("epidemiology/infection/health_index.jl")
include("epidemiology/infection/trajectory.jl")
include("epidemiology/infection/infection_selector.jl")
include("epidemiology/immunity.jl")
include("epidemiology/infection_seed/infection_seed.jl")
include("epidemiology/vaccines/vaccine.jl")
include("epidemiology/vaccines/vaccination_campaign.jl")
include("epidemiology/epidemiology.jl")

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------
include("interaction/interaction.jl")

# ---------------------------------------------------------------------------
# Time & Activity
# ---------------------------------------------------------------------------
include("time.jl")
include("activity/activity_manager.jl")

# ---------------------------------------------------------------------------
# Demography (full — depends on geography)
# ---------------------------------------------------------------------------
include("demography/demography.jl")

# ---------------------------------------------------------------------------
# Distributors
# ---------------------------------------------------------------------------
include("distributors/worker_distributor.jl")
include("distributors/household_distributor.jl")
include("distributors/school_distributor.jl")
include("distributors/company_distributor.jl")
include("distributors/hospital_distributor.jl")
include("distributors/university_distributor.jl")
include("distributors/care_home_distributor.jl")

# ---------------------------------------------------------------------------
# Policy & Events
# ---------------------------------------------------------------------------
include("policy/policy.jl")
include("event/event.jl")

# ---------------------------------------------------------------------------
# Records & Tracker
# ---------------------------------------------------------------------------
include("records/records.jl")
include("tracker/tracker.jl")

# ---------------------------------------------------------------------------
# World & Simulator
# ---------------------------------------------------------------------------
include("world.jl")
include("simulator.jl")

# ---------------------------------------------------------------------------
# HDF5 I/O
# ---------------------------------------------------------------------------
include("hdf5_savers/world_saver.jl")

# ---------------------------------------------------------------------------
# MPI (optional)
# ---------------------------------------------------------------------------
include("mpi_setup.jl")

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------
export
    # Core types
    Person, Activities, Population, SymptomTag,
    # SymptomTag enum values
    recovered, healthy, exposed, asymptomatic, mild, severe,
    hospitalised, intensive_care, dead_home, dead_hospital, dead_icu,
    # SymptomTag functions
    symptom_value, symptom_from_value, symptom_from_string,
    is_dead, should_be_in_hospital,
    # Person functions
    is_infected, is_available, reset_person_ids!, next_person_id!,
    # Population functions
    get_from_id, infected, dead_people, vaccinated, extend!, members,
    # Geography
    Area, SuperArea, Region, Areas, SuperAreas, Regions, Geography,
    ExternalSuperArea,
    geography_from_file, create_geographical_units,
    get_closest_areas, get_closest_super_areas,
    reset_geography_counters!, add_worker!, remove_worker!, closed_venues,
    # Groups
    AbstractGroup, Subgroup, Group, Supergroup, InteractiveGroup,
    reset_group_ids!, next_group_id!, people, eachperson, clear!,
    Household, Households, School, Schools, Company, Companies,
    Hospital, Hospitals, CareHome, CareHomes, University, Universities,
    Cemetery, Cemeteries,
    Pub, Pubs, Cinema, Cinemas, Grocery, Groceries, Gym, Gyms,
    Leisure, SocialVenue, SocialVenues,
    # Household functions
    n_residents,
    # School functions
    n_pupils, n_teachers, is_full,
    # Hospital functions
    add_to_ward!, add_to_icu!, allocate_patient!, release_patient!,
    # Epidemiology
    Infection, Immunity, ImmunitySetter,
    TransmissionGamma, TransmissionXNExp, TransmissionConstant,
    Symptoms, InfectionSelector, InfectionSelectors,
    HealthIndexGenerator, TrajectoryMaker,
    InfectionSeed, InfectionSeeds,
    Vaccine, Dose, VaccineTrajectory, VaccinationCampaign, VaccinationCampaigns,
    Epidemiology_,
    # Transmission functions
    update_infection_probability!,
    # Infection functions
    update_health_status!, infection_probability,
    get_susceptibility, get_effective_multiplier, add_immunity!, is_immune,
    # Symptoms functions
    set_trajectory!, update_trajectory_stage!,
    # Infection selector functions
    infect_person_at_time!, infection_selector_from_file,
    # Epidemiology functions
    recover!, bury_the_dead!,
    # Interaction
    Interaction,
    interaction_from_file, time_step_for_group!,
    # Time & Activity
    Timer, ActivityManager,
    timer_from_file, advance!, activities, day_type, is_weekend,
    # Activity manager functions
    activity_manager_from_file, move_people_to_active_subgroups!,
    # Demography
    Demography, AgeSexGenerator, ComorbidityGenerator,
    demography_for_areas, demography_for_geography,
    populate!, generate_age, generate_sex,
    # Distributors
    HouseholdDistributor, SchoolDistributor, CompanyDistributor,
    HospitalDistributor, UniversityDistributor, CareHomeDistributor,
    WorkerDistributor,
    # Policy & Events
    Policy, Policies, Events,
    policies_from_file, is_active,
    apply_individual!, apply_interaction!, apply_leisure!,
    apply_medical_care!, apply_regional_compliance!,
    # Records
    Record,
    accumulate_infection!, time_step!, static_data!,
    # World & Simulator
    World, Simulator, generate_world_from_geography,
    distribute_people!, clear_world!,
    simulator_from_file, do_timestep!, save_checkpoint,
    # HDF5 I/O
    save_world_to_hdf5, load_world_from_hdf5,
    # Functions
    run!, add!, remove!

end # module
