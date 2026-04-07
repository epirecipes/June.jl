using Test
using June
using Dates
using DataFrames
using Random

function make_test_timer(; start=DateTime(2020, 3, 2, 9), total_days=1)
    return June.Timer(
        start,
        total_days,
        start,
        start,
        start + Day(total_days),
        0,
        0.0,
        [12.0, 12.0],
        [12.0, 12.0],
        [["residence", "primary_activity"], ["residence", "leisure"]],
        [["residence", "leisure"], ["residence", "leisure"]],
        Dates.Millisecond(0),
        0.5,
    )
end

function make_test_selector(infection_id::Int=0; probability::Float64=1.0)
    health_row = Float64[0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    health_data = repeat(reshape(health_row, 1, :), 100, 1)
    trajectory = Tuple{String, Dict}[
        ("exposed", Dict("value" => 0.0)),
        ("mild", Dict("value" => 1.0)),
        ("recovered", Dict("value" => 0.0)),
    ]
    trajectory_maker = TrajectoryMaker(Dict(mild => [trajectory]))
    return InfectionSelector(
        infection_id,
        Dict("type" => "constant", "probability" => probability),
        trajectory_maker,
        HealthIndexGenerator(; female_data=health_data, male_data=health_data),
    )
end

@testset "June.jl" begin
    @testset "SymptomTag" begin
        @test symptom_value(recovered) == -3
        @test symptom_value(healthy) == -2
        @test symptom_value(exposed) == -1
        @test symptom_value(asymptomatic) == 0
        @test symptom_value(mild) == 1
        @test symptom_value(severe) == 2
        @test symptom_value(hospitalised) == 3
        @test symptom_value(intensive_care) == 4
        @test symptom_value(dead_home) == 5
        @test symptom_value(dead_hospital) == 6
        @test symptom_value(dead_icu) == 7

        @test is_dead(dead_home)
        @test is_dead(dead_hospital)
        @test is_dead(dead_icu)
        @test !is_dead(mild)
        @test should_be_in_hospital(hospitalised)
        @test should_be_in_hospital(intensive_care)
        @test !should_be_in_hospital(mild)
    end

    @testset "Person" begin
        reset_person_ids!()
        p1 = Person(; sex='f', age=30)
        p2 = Person(; sex='m', age=45)

        @test p1.id == 1
        @test p2.id == 2
        @test p1.sex == 'f'
        @test p2.sex == 'm'
        @test p1.age == 30
        @test !p1.dead
        @test !is_infected(p1)
        @test is_available(p1)

        # Activities
        @test isnothing(p1.subgroups.residence)
        @test isnothing(p1.subgroups.primary_activity)
    end

    @testset "Population" begin
        reset_person_ids!()
        pop = Population()
        @test length(pop) == 0

        p1 = Person(; age=25)
        p2 = Person(; age=30)
        push!(pop, p1)
        push!(pop, p2)

        @test length(pop) == 2
        @test get_from_id(pop, p1.id) === p1
        @test collect(pop) == [p1, p2]

        remove!(pop, p1)
        @test length(pop) == 1
    end

    @testset "Geography Types" begin
        reset_geography_counters!()
        area = Area(; name="E00001", coordinates=(51.5, -0.1), socioeconomic_index=0.5)
        @test area.name == "E00001"
        @test area.coordinates == (51.5, -0.1)

        sa = SuperArea(; name="E02000001", coordinates=(51.5, -0.1), areas=[area])
        area.super_area = sa
        @test area.super_area === sa

        region = Region(; name="London", super_areas=[sa])
        sa.region = region
        @test sa.region === region
    end

    @testset "Group Hierarchy" begin
        reset_group_ids!()

        g = Group("test_group", 3)
        @test g.id == 1
        @test g.spec == "test_group"
        @test length(g.subgroups) == 3

        p = Person(; age=25)
        add!(g, p, 1)
        @test length(people(g)) == 1
        @test p in g.subgroups[1]

        clear!(g)
        @test length(people(g)) == 0
    end

    @testset "Supergroup" begin
        reset_group_ids!()
        g1 = Group("household", 4)
        g2 = Group("household", 4)
        sg = Supergroup("households", [g1, g2])

        @test length(sg) == 2
        @test get_from_id(sg, g1.id) === g1
    end

    @testset "Household" begin
        reset_group_ids!()
        h = Household(; type="family")
        @test h.type == "family"

        p = Person(; age=35)
        add!(h, p; activity=:residence)
        @test p.id in h.residents
        @test length(people(h)) == 1
    end

    @testset "School" begin
        reset_group_ids!()
        s = School((51.5, -0.1), 200, 5, 11, "primary")
        @test s.age_min == 5
        @test s.age_max == 11
        @test s.sector == "primary"

        child = Person(; age=8)
        add!(s, child)
        @test n_pupils(s) >= 1

        teacher = Person(; age=35)
        add!(s, teacher)
        @test n_teachers(s) >= 1
    end

    @testset "Hospital" begin
        reset_group_ids!()
        h = Hospital()
        p = Person(; age=60)
        add_to_ward!(h, p)
        @test p.id in h.ward_ids
        release_patient!(h, p)
        @test !(p.id in h.ward_ids)
    end

    @testset "Cemetery" begin
        c = Cemetery()
        p = Person(; age=80)
        add!(c, p)
        @test p.dead
    end

    @testset "Transmission" begin
        tc = TransmissionConstant(0.5)
        @test tc.probability == 0.5

        tg = TransmissionGamma(0.3, 1.56, 0.53, -2.12)
        @test tg.probability == 0.0
        update_infection_probability!(tg, 1.0)
        @test tg.probability >= 0.0
    end

    @testset "Symptoms" begin
        health_index = [0.1, 0.3, 0.6, 0.8, 0.9, 0.95, 0.99, 1.0]
        s = Symptoms(health_index)
        @test s.tag == exposed
        @test s.max_severity >= 0.0
        @test s.max_severity <= 1.0
    end

    @testset "Immunity" begin
        imm = Immunity()
        @test get_susceptibility(imm, 0) == 1.0
        add_immunity!(imm, [0])
        @test get_susceptibility(imm, 0) == 0.0
        @test is_immune(imm, 0)
    end

    @testset "Timer" begin
        # March 2, 2020 is a Monday (weekday)
        t = June.Timer(
            DateTime(2020, 3, 2, 9),
            5,
            DateTime(2020, 3, 2, 9),
            DateTime(2020, 3, 2, 9),
            DateTime(2020, 3, 7, 9),
            0,
            0.0,
            [12.0, 12.0],
            [12.0, 12.0],
            [["residence", "primary_activity"], ["residence", "leisure"]],
            [["residence", "leisure"], ["residence", "leisure"]],
            Dates.Millisecond(0),
            0.5
        )
        @test t.total_days == 5
        @test day_type(t) == "weekday"
        acts = activities(t)
        @test "residence" in acts
    end

    @testset "Interaction" begin
        inter = Interaction(0.5, Dict("household" => 3.0),
                           Dict("household" => ones(4, 4)),
                           Dict{String, Float64}())
        @test inter.alpha_physical == 0.5
        @test inter.betas["household"] == 3.0
    end

    @testset "Immunity setter uses world.people" begin
        reset_person_ids!()
        world = World()
        world.people = Population()
        person = Person(; age=75)
        push!(world.people, person)

        setter = ImmunitySetter(
            Dict(0 => Dict("65+" => 0.2)),
            Dict(0 => Dict("65+" => 0.5)),
            :average,
        )
        June.set_immunity!(setter, world)

        @test person.immunity !== nothing
        @test get_susceptibility(person.immunity, 0) == 0.2
        @test get_effective_multiplier(person.immunity, 0) == 0.5
    end

    @testset "Activity manager applies individual policies" begin
        reset_person_ids!()
        reset_group_ids!()

        person = Person(; age=30)
        household = Household()
        add!(household, person; activity=:residence)

        school_group = Group("school", 1)
        person.subgroups.primary_activity = school_group.subgroups[1]

        world = World()
        world.people = Population()
        push!(world.people, person)
        world.households = June.create_households([household])
        world.schools = Supergroup("schools", [school_group])

        policies = Policies()
        push!(policies.individual_policies, June.StayHome(nothing, nothing, 1.0))

        am = ActivityManager(
            Dict(
                "residence" => ["households"],
                "primary_activity" => ["schools"],
            ),
            ["households", "schools"],
            String[],
            policies,
            nothing,
            nothing,
        )

        do_timestep!(am, make_test_timer(); world=world)

        @test person in household.group.subgroups[3]
        @test !(person in school_group.subgroups[1])
    end

    @testset "Interaction keeps infection variant ids" begin
        reset_person_ids!()
        reset_group_ids!()
        Random.seed!(1234)

        group = Group("household", 1)
        infector = Person(; age=40)
        susceptible = Person(; age=20)
        add!(group, infector, 1)
        add!(group, susceptible, 1)

        infector.infection = Infection(
            TransmissionConstant(1.0),
            Symptoms(severe, severe, 1.0, Tuple{Float64, SymptomTag}[], 1, 0.0),
            0.0;
            infection_id=7,
        )

        interaction = Interaction(
            1.0,
            Dict("household" => 10.0),
            Dict("household" => ones(1, 1)),
            Dict{String, Float64}(),
        )

        infected_ids, infection_ids, _ = time_step_for_group!(interaction, group; delta_time=1.0)
        @test infected_ids == [susceptible.id]
        @test infection_ids == [7]
    end

    @testset "Regional policies update live region fields" begin
        reset_geography_counters!()
        reset_group_ids!()

        area = Area(; name="A")
        super_area = SuperArea(; name="SA", areas=[area])
        area.super_area = super_area
        region = Region(; name="London", super_areas=[super_area])
        super_area.region = region

        group = Group("household", 1; area=area)
        ig = InteractiveGroup(group)

        policies = Policies()
        push!(policies.regional_compliance, June.RegionalCompliance(nothing, nothing, Dict("London" => 0.25)))
        push!(policies.regional_compliance, June.TieredLockdown(nothing, nothing, Dict("London" => 4)))

        apply_regional_compliance!(policies, DateTime(2020, 3, 2, 9), Regions([region]))

        @test region.regional_compliance == 0.25
        @test region.lockdown_tier == 4
        @test June.get_processed_beta(ig, 2.0; beta_reductions=Dict("household" => 0.5)) ≈ 1.875
    end

    @testset "Infection seeds resolve region names" begin
        reset_person_ids!()
        reset_geography_counters!()

        area = Area(; name="Area-1")
        super_area = SuperArea(; name="Super-1", areas=[area])
        area.super_area = super_area
        region = Region(; name="London", super_areas=[super_area])
        super_area.region = region

        world = World()
        world.areas = Areas([area])
        world.super_areas = SuperAreas([super_area])
        world.regions = Regions([region])
        world.people = Population()

        person = Person(; age=35)
        add!(area, person)
        push!(world.people, person)

        seed = InfectionSeed(
            make_test_selector(5; probability=1.0),
            DataFrame(date=[DateTime(2020, 3, 2, 9)], London=[1.0]),
        )

        June.infection_seeds_timestep!(InfectionSeeds([seed]), world, make_test_timer(), nothing)

        @test is_infected(person)
        @test person.infection.infection_id == 5
    end

    @testset "Vaccination campaigns are applied during epidemiology steps" begin
        reset_person_ids!()

        person = Person(; age=80)
        world = World()
        world.people = Population()
        push!(world.people, person)

        vaccine = Vaccine(
            "test-vaccine",
            [
                Dict(
                    "sterilisation_efficacy" => Dict(0 => 0.8),
                    "symptomatic_efficacy" => Dict(0 => 0.5),
                    "days_administered_to_effective" => 0.0,
                    "days_effective_to_waning" => 100.0,
                    "days_waning" => 10.0,
                ),
                Dict(
                    "sterilisation_efficacy" => Dict(0 => 0.9),
                    "symptomatic_efficacy" => Dict(0 => 0.7),
                    "days_administered_to_effective" => 0.0,
                    "days_effective_to_waning" => 100.0,
                    "days_waning" => 10.0,
                ),
            ],
            0.5,
        )
        campaign = VaccinationCampaign(
            vaccine,
            DateTime(2020, 3, 2, 0),
            DateTime(2020, 3, 5, 0),
            "age",
            "70+",
            1.0,
            [1, 2],
            [21.0],
        )
        epi = Epidemiology_(nothing, nothing, nothing, VaccinationCampaigns([campaign]))
        timer = make_test_timer()

        do_timestep!(epi, world, timer, nothing)
        @test person.vaccinated == 1
        @test person.immunity !== nothing
        @test get_susceptibility(person.immunity, 0) ≈ 0.2

        do_timestep!(epi, world, timer, nothing)
        @test person.vaccinated == 1
    end

    @testset "Simulator flushes record buffers each timestep" begin
        reset_person_ids!()
        reset_group_ids!()

        person = Person(; age=40)
        household = Household()
        add!(household, person; activity=:residence)

        world = World()
        world.people = Population()
        push!(world.people, person)
        world.households = June.create_households([household])
        world.cemeteries = Cemeteries()

        activity_manager = ActivityManager(
            Dict("residence" => ["households"]),
            ["households"],
            String[],
            nothing,
            nothing,
            nothing,
        )
        interaction = Interaction(
            1.0,
            Dict("household" => 0.0),
            Dict("household" => ones(4, 4)),
            Dict{String, Float64}(),
        )
        record = Record(; record_path=mktempdir(), record_static_data=false)
        accumulate_infection!(record; person_id=person.id, infection_id=0, source="test")

        sim = Simulator(
            world,
            interaction,
            make_test_timer(),
            activity_manager,
            nothing,
            nothing,
            nothing,
            record,
            Date[],
            "",
        )

        do_timestep!(sim)

        @test isfile(joinpath(record.record_path, "records.h5"))
        @test isempty(record.infection_buffer)
    end
end
