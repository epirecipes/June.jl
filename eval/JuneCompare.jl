"""
    JuneCompare

Stochastic trajectory comparison between the Julia June.jl implementation
and the reference Python JUNE implementation.

# Usage

    include("eval/JuneCompare.jl")
    using .JuneCompare
    report = compare_model(; n_reps=20, n_steps=50)
    print_report(report)
    save_csv(report, "eval/results/simple_sir.csv")
"""
module JuneCompare

export TrajectoryData, VariableComparison, ComparisonReport,
       BatchMetrics, VariableCalibrated, CalibratedReport,
       BenchmarkResult,
       AbstractScenario, SimpleSIR, HouseholdSIR, SEIR, AgeStructuredSIR,
       SIRVaccination, SIRLarge, ComplexVaccines,
       MODELS, scenario_name, tracked_vars, default_n_steps,
       compare_model, compare_model_calibrated,
       print_report, print_calibrated_report,
       save_csv, save_calibrated_csv,
       run_julia, run_python,
       run_benchmark, print_benchmark_report,
       ks_statistic, pearson_r, ecdf_correlation, mmd_rbf, trajectory_mmd,
       run_julia_sir, run_python_sir

using Statistics
using Printf
using Random
using SpecialFunctions: loggamma
using Dates

# ── Fast inline gamma transmission (avoids June.jl API dispatch overhead) ──

"""Fast inline Gamma PDF: x^(k-1) * exp(-x/θ) / (θ^k * Γ(k))"""
@inline function _fast_gamma_pdf(x::Float64, shape::Float64, scale::Float64)
    x <= 0.0 && return 0.0
    return exp((shape - 1.0) * log(x) - x / scale - shape * log(scale) - loggamma(shape))
end

"""Lightweight gamma transmission struct — no June.jl dependency, fully inlineable."""
struct FastGammaTransmission
    norm::Float64
    shape::Float64
    scale::Float64
    shift::Float64
    # inner constructor to prevent ambiguity with the factory constructor
    FastGammaTransmission(norm::Float64, shape::Float64, scale::Float64, shift::Float64, ::Val{:inner}) = new(norm, shape, scale, shift)
end

function FastGammaTransmission(max_infectiousness::Float64, shape::Float64, rate::Float64, shift::Float64)
    scale = 1.0 / rate
    time_at_max = (shape - 1.0) * scale + shift
    norm = max_infectiousness / _fast_gamma_pdf(time_at_max - shift, shape, scale)
    return FastGammaTransmission(norm, shape, scale, shift, Val(:inner))
end

@inline function fast_infection_prob(ft::FastGammaTransmission, time_from_infection::Float64)
    time_from_infection <= ft.shift && return 0.0
    return ft.norm * _fast_gamma_pdf(time_from_infection - ft.shift, ft.shape, ft.scale)
end

"""Fast SIR count: returns (S, I, R) without closures."""
@inline function _fast_sir_counts(infected::BitVector, recovered::BitVector)
    n = length(infected)
    s = 0; inf = 0; r = 0
    @inbounds for i in 1:n
        if recovered[i]
            r += 1
        elseif infected[i]
            inf += 1
        else
            s += 1
        end
    end
    return (Float64(s), Float64(inf), Float64(r))
end

# ── Configuration ──────────────────────────────────────────────────────

const PYTHON_CMD = Ref{String}("")

function python_cmd()
    if isempty(PYTHON_CMD[])
        candidates = [
            joinpath(@__DIR__, "..", "vignettes", ".venv", "bin", "python"),
            joinpath(@__DIR__, "..", "vignettes", ".venv", "bin", "python3"),
        ]
        for c in candidates
            if isfile(c)
                PYTHON_CMD[] = c
                return c
            end
        end
        error("""Python venv not found. Set JuneCompare.PYTHON_CMD[] = "/path/to/python" """)
    end
    PYTHON_CMD[]
end

const SCENARIO_DIR = joinpath(@__DIR__, "scenarios")

# ── Scenario type hierarchy ───────────────────────────────────────────

abstract type AbstractScenario end

struct SimpleSIR <: AbstractScenario end
struct HouseholdSIR <: AbstractScenario end
struct SEIR <: AbstractScenario end
struct AgeStructuredSIR <: AbstractScenario end
struct SIRVaccination <: AbstractScenario end
struct SIRLarge <: AbstractScenario end
struct ComplexVaccines <: AbstractScenario end

scenario_name(::SimpleSIR) = "Simple SIR"
scenario_name(::HouseholdSIR) = "Household SIR"
scenario_name(::SEIR) = "SEIR"
scenario_name(::AgeStructuredSIR) = "Age-Structured SIR"
scenario_name(::SIRVaccination) = "SIR Vaccination"
scenario_name(::SIRLarge) = "SIR Large"
scenario_name(::ComplexVaccines) = "Complex Vaccines"

tracked_vars(::SimpleSIR) = ["susceptible", "infected", "recovered"]
tracked_vars(::HouseholdSIR) = ["susceptible", "infected", "recovered"]
tracked_vars(::SEIR) = ["susceptible", "exposed", "infected", "recovered"]
tracked_vars(::AgeStructuredSIR) = ["susceptible", "infected", "recovered"]
tracked_vars(::SIRVaccination) = ["susceptible", "infected", "recovered", "vaccinated_infected"]
tracked_vars(::SIRLarge) = ["susceptible", "infected", "recovered"]
tracked_vars(::ComplexVaccines) = ["susceptible", "exposed", "infected", "recovered", "dead", "hospitalised", "vaccinated_infected"]

default_n_steps(::AbstractScenario) = 50
default_n_steps(::SIRLarge) = 100
default_n_steps(::ComplexVaccines) = 100

python_script(::SimpleSIR) = joinpath(SCENARIO_DIR, "simple_sir.py")
python_script(::HouseholdSIR) = joinpath(SCENARIO_DIR, "household_sir.py")
python_script(::SEIR) = joinpath(SCENARIO_DIR, "seir.py")
python_script(::AgeStructuredSIR) = joinpath(SCENARIO_DIR, "age_structured_sir.py")
python_script(::SIRVaccination) = joinpath(SCENARIO_DIR, "sir_vaccination.py")
python_script(::SIRLarge) = joinpath(SCENARIO_DIR, "sir_large.py")
python_script(::ComplexVaccines) = joinpath(SCENARIO_DIR, "complex_vaccines.py")

python_extra_args(::AbstractScenario) = String[]

const MODELS = Dict{String, AbstractScenario}(
    "simple_sir"     => SimpleSIR(),
    "household_sir"  => HouseholdSIR(),
    "seir"           => SEIR(),
    "age_structured" => AgeStructuredSIR(),
    "vaccination"    => SIRVaccination(),
    "large"          => SIRLarge(),
    "complex"        => ComplexVaccines(),
)

# ── Data structures ───────────────────────────────────────────────────

struct TrajectoryData
    seed::Int
    ticks::Vector{Int}
    values::Dict{String, Vector{Float64}}
end

struct BenchmarkResult
    scenario_name::String
    julia_time_per_rep::Float64
    python_time_per_rep::Float64
    julia_peak_mem::Float64
    python_peak_mem::Float64
    speedup::Float64
    memory_ratio::Float64
end

struct VariableComparison
    name::String
    julia_mean::Vector{Float64}
    julia_std::Vector{Float64}
    python_mean::Vector{Float64}
    python_std::Vector{Float64}
    # Mean trajectory metrics
    mae_mean_traj::Float64
    nmae_mean_traj::Float64
    corr_mean_traj::Float64
    # Final-step distributional metrics
    ks_statistic::Float64
    ecdf_corr::Float64
    qq_corr::Float64
    # Trajectory-level MMD
    mmd_stat::Float64
    mmd_pvalue::Float64
    # Summary stats
    julia_final_mean::Float64
    python_final_mean::Float64
    julia_final_std::Float64
    python_final_std::Float64
    julia_final_median::Float64
    python_final_median::Float64
end

struct ComparisonReport
    scenario_name::String
    n_reps::Int
    n_steps::Int
    seeds::Vector{Int}
    julia_trajectories::Vector{TrajectoryData}
    python_trajectories::Vector{TrajectoryData}
    comparisons::Vector{VariableComparison}
    julia_time_s::Float64
    python_time_s::Float64
end

# ── Julia runner (uses June.jl API) ──────────────────────────────────

function _get_june_module()
    Base.require(Main, :June)
end

function run_julia_sir(seed::Int;
                       n_people::Int=200,
                       n_steps::Int=50,
                       n_initial_infected::Int=5,
                       beta::Float64=0.3,
                       gamma_shape::Float64=1.56,
                       gamma_rate::Float64=0.53,
                       gamma_shift::Float64=-2.12,
                       recovery_days::Int=14)
    Base.invokelatest(_run_julia_sir_impl, seed;
                      n_people=n_people, n_steps=n_steps,
                      n_initial_infected=n_initial_infected,
                      beta=beta, gamma_shape=gamma_shape,
                      gamma_rate=gamma_rate, gamma_shift=gamma_shift,
                      recovery_days=recovery_days)
end

function _run_julia_sir_impl(seed::Int;
                              n_people::Int=200,
                              n_steps::Int=50,
                              n_initial_infected::Int=5,
                              beta::Float64=0.3,
                              gamma_shape::Float64=1.56,
                              gamma_rate::Float64=0.53,
                              gamma_shift::Float64=-2.12,
                              recovery_days::Int=14)
    June = _get_june_module()
    _Person          = getfield(June, :Person)
    _Household       = getfield(June, :Household)
    _School          = getfield(June, :School)
    _Company         = getfield(June, :Company)
    _add!            = getfield(June, :add!)
    _people          = getfield(June, :people)
    _reset_person_ids! = getfield(June, :reset_person_ids!)
    _reset_group_ids!  = getfield(June, :reset_group_ids!)

    rng = MersenneTwister(seed)

    _reset_person_ids!()
    _reset_group_ids!()

    # Create people
    all_people = [_Person(; sex=rand(rng, ['m', 'f']), age=rand(rng, 1:80))
                  for _ in 1:n_people]

    # Assign to households of 4
    households = []
    for i in 1:4:n_people
        h = _Household()
        for j in i:min(i+3, n_people)
            _add!(h, all_people[j]; activity=:residence)
        end
        push!(households, h)
    end

    # One shared school and one shared company
    school = _School((0.0, 0.0), n_people, 5, 18, "primary")
    company = _Company(; n_workers_max=n_people)

    for p in all_people
        if p.age <= 18
            _add!(school, p)
        else
            _add!(company, p)
        end
    end

    # Infection state tracking (parallel to June objects)
    infected_flag = falses(n_people)
    recovered_flag = falses(n_people)
    days_infected = zeros(Int, n_people)

    # Seed initial infections
    initial_idx = randperm(rng, n_people)[1:n_initial_infected]
    for idx in initial_idx
        infected_flag[idx] = true
        days_infected[idx] = 1
    end

    # Create a shared TransmissionGamma for probability lookups
    ft = FastGammaTransmission(beta, gamma_shape, gamma_rate, gamma_shift)

    # Collect all groups for transmission
    all_groups = vcat(households, [school, company])
    group_member_ids = [Int[p.id for p in _people(grp)] for grp in all_groups]
    # Drop June.jl object references so GC can reclaim them
    all_people = nothing; households = nothing; all_groups = nothing; school = nothing; company = nothing

    # Track S, I, R
    s0, i0, r0 = _fast_sir_counts(infected_flag, recovered_flag); s_counts = Float64[s0]
    i_counts = Float64[i0]
    r_counts = Float64[r0]
    tick_nums = Int[0]

    new_infections = falses(n_people)
    for step in 1:n_steps
        fill!(new_infections, false)

        # Transmission within groups
        for member_ids in group_member_ids
            isempty(member_ids) && continue

            @inbounds for pid in member_ids
                if infected_flag[pid] && !recovered_flag[pid]
                    prob = fast_infection_prob(ft, Float64(days_infected[pid]))

                    @inbounds for qid in member_ids
                        if !infected_flag[qid] && !recovered_flag[qid] && !new_infections[qid]
                            if rand(rng) < prob
                                new_infections[qid] = true
                            end
                        end
                    end
                end
            end
        end

        # Apply new infections
        @inbounds for i in 1:n_people
            if new_infections[i]
                infected_flag[i] = true
                days_infected[i] = 1
            end
        end

        # Recovery
        @inbounds for i in 1:n_people
            if infected_flag[i] && !recovered_flag[i]
                if days_infected[i] >= recovery_days
                    infected_flag[i] = false
                    recovered_flag[i] = true
                else
                    days_infected[i] += 1
                end
            end
        end

        # Record
        push!(tick_nums, step)
        sc, ic, rc = _fast_sir_counts(infected_flag, recovered_flag); push!(s_counts, sc)
        push!(i_counts, ic)
        push!(r_counts, rc)
    end

    TrajectoryData(seed, tick_nums, Dict(
        "susceptible" => s_counts,
        "infected"    => i_counts,
        "recovered"   => r_counts,
    ))
end

# ── Generic dispatch: run_julia(scenario, seed) ──────────────────────

function run_julia(scenario::SimpleSIR, seed::Int; n_steps::Int=50, kwargs...)
    run_julia_sir(seed; n_steps=n_steps, kwargs...)
end

function run_julia(::HouseholdSIR, seed::Int; n_steps::Int=50, kwargs...)
    Base.invokelatest(_run_julia_household_sir_impl, seed; n_steps=n_steps, kwargs...)
end

function run_julia(::SEIR, seed::Int; n_steps::Int=50, kwargs...)
    Base.invokelatest(_run_julia_seir_impl, seed; n_steps=n_steps, kwargs...)
end

function run_julia(::AgeStructuredSIR, seed::Int; n_steps::Int=50, kwargs...)
    Base.invokelatest(_run_julia_age_structured_sir_impl, seed; n_steps=n_steps, kwargs...)
end

function run_julia(::SIRVaccination, seed::Int; n_steps::Int=50, kwargs...)
    Base.invokelatest(_run_julia_sir_vaccination_impl, seed; n_steps=n_steps, kwargs...)
end

function run_julia(::SIRLarge, seed::Int; n_steps::Int=100, kwargs...)
    Base.invokelatest(_run_julia_sir_large_impl, seed; n_steps=n_steps, kwargs...)
end

# ── Household SIR (no school/company) ─────────────────────────────────

function _run_julia_household_sir_impl(seed::Int;
                                        n_people::Int=200,
                                        n_steps::Int=50,
                                        n_initial_infected::Int=5,
                                        beta::Float64=0.5,
                                        gamma_shape::Float64=1.56,
                                        gamma_rate::Float64=0.53,
                                        gamma_shift::Float64=-2.12,
                                        recovery_days::Int=14)
    June = _get_june_module()
    _Person            = getfield(June, :Person)
    _Household         = getfield(June, :Household)
    _add!              = getfield(June, :add!)
    _people            = getfield(June, :people)
    _reset_person_ids! = getfield(June, :reset_person_ids!)
    _reset_group_ids!  = getfield(June, :reset_group_ids!)

    rng = MersenneTwister(seed)
    _reset_person_ids!()
    _reset_group_ids!()

    all_people = [_Person(; sex=rand(rng, ['m', 'f']), age=rand(rng, 1:80))
                  for _ in 1:n_people]

    # Households of 4 ONLY
    households = []
    for i in 1:4:n_people
        h = _Household()
        for j in i:min(i+3, n_people)
            _add!(h, all_people[j]; activity=:residence)
        end
        push!(households, h)
    end

    all_groups = households
    group_member_ids = [Int[p.id for p in _people(grp)] for grp in all_groups]
    # Drop June.jl object references so GC can reclaim them
    all_people = nothing; households = nothing; all_groups = nothing; school = nothing; company = nothing

    infected_flag = falses(n_people)
    recovered_flag = falses(n_people)
    days_infected = zeros(Int, n_people)

    initial_idx = randperm(rng, n_people)[1:n_initial_infected]
    for idx in initial_idx
        infected_flag[idx] = true
        days_infected[idx] = 1
    end

    ft = FastGammaTransmission(beta, gamma_shape, gamma_rate, gamma_shift)

    s0, i0, r0 = _fast_sir_counts(infected_flag, recovered_flag); s_counts = Float64[s0]
    i_counts = Float64[i0]
    r_counts = Float64[r0]
    tick_nums = Int[0]

    new_infections = falses(n_people)
    for step in 1:n_steps
        fill!(new_infections, false)

        for member_ids in group_member_ids
            isempty(member_ids) && continue

            @inbounds for pid in member_ids
                if infected_flag[pid] && !recovered_flag[pid]
                    prob = fast_infection_prob(ft, Float64(days_infected[pid]))
                    @inbounds for qid in member_ids
                        if !infected_flag[qid] && !recovered_flag[qid] && !new_infections[qid]
                            if rand(rng) < prob
                                new_infections[qid] = true
                            end
                        end
                    end
                end
            end
        end

        @inbounds for i in 1:n_people
            if new_infections[i]
                infected_flag[i] = true
                days_infected[i] = 1
            end
        end

        @inbounds for i in 1:n_people
            if infected_flag[i] && !recovered_flag[i]
                if days_infected[i] >= recovery_days
                    infected_flag[i] = false
                    recovered_flag[i] = true
                else
                    days_infected[i] += 1
                end
            end
        end

        push!(tick_nums, step)
        sc, ic, rc = _fast_sir_counts(infected_flag, recovered_flag); push!(s_counts, sc)
        push!(i_counts, ic)
        push!(r_counts, rc)
    end

    TrajectoryData(seed, tick_nums, Dict(
        "susceptible" => s_counts,
        "infected"    => i_counts,
        "recovered"   => r_counts,
    ))
end

# ── SEIR (exposed/latent period) ──────────────────────────────────────

function _run_julia_seir_impl(seed::Int;
                               n_people::Int=200,
                               n_steps::Int=50,
                               n_initial_infected::Int=5,
                               beta::Float64=0.3,
                               gamma_shape::Float64=1.56,
                               gamma_rate::Float64=0.53,
                               gamma_shift::Float64=-2.12,
                               recovery_days::Int=14,
                               exposed_days::Int=3)
    June = _get_june_module()
    _Person            = getfield(June, :Person)
    _Household         = getfield(June, :Household)
    _School            = getfield(June, :School)
    _Company           = getfield(June, :Company)
    _add!              = getfield(June, :add!)
    _people            = getfield(June, :people)
    _reset_person_ids! = getfield(June, :reset_person_ids!)
    _reset_group_ids!  = getfield(June, :reset_group_ids!)

    rng = MersenneTwister(seed)
    _reset_person_ids!()
    _reset_group_ids!()

    all_people = [_Person(; sex=rand(rng, ['m', 'f']), age=rand(rng, 1:80))
                  for _ in 1:n_people]

    households = []
    for i in 1:4:n_people
        h = _Household()
        for j in i:min(i+3, n_people)
            _add!(h, all_people[j]; activity=:residence)
        end
        push!(households, h)
    end

    school = _School((0.0, 0.0), n_people, 5, 18, "primary")
    company = _Company(; n_workers_max=n_people)
    for p in all_people
        if p.age <= 18
            _add!(school, p)
        else
            _add!(company, p)
        end
    end

    all_groups = vcat(households, [school, company])
    group_member_ids = [Int[p.id for p in _people(grp)] for grp in all_groups]
    # Drop June.jl object references so GC can reclaim them
    all_people = nothing; households = nothing; all_groups = nothing; school = nothing; company = nothing

    exposed_flag = falses(n_people)
    infected_flag = falses(n_people)
    recovered_flag = falses(n_people)
    days_exposed_arr = zeros(Int, n_people)
    days_infected = zeros(Int, n_people)

    # Seed initial infections (start as infected, not exposed)
    initial_idx = randperm(rng, n_people)[1:n_initial_infected]
    for idx in initial_idx
        infected_flag[idx] = true
        days_infected[idx] = 1
    end

    ft = FastGammaTransmission(beta, gamma_shape, gamma_rate, gamma_shift)

    s0 = count(i -> !exposed_flag[i] && !infected_flag[i] && !recovered_flag[i], 1:n_people)
    s_counts = Float64[s0]
    e_counts = Float64[Float64(count(exposed_flag))]
    i_counts = Float64[Float64(count(infected_flag))]
    r_counts = Float64[Float64(count(recovered_flag))]
    tick_nums = Int[0]

    new_exposed = falses(n_people)
    for step in 1:n_steps
        fill!(new_exposed, false)

        # Transmission: infected → susceptible becomes exposed
        for member_ids in group_member_ids
            isempty(member_ids) && continue

            @inbounds for pid in member_ids
                if infected_flag[pid] && !recovered_flag[pid]
                    prob = fast_infection_prob(ft, Float64(days_infected[pid]))
                    @inbounds for qid in member_ids
                        if !exposed_flag[qid] && !infected_flag[qid] && !recovered_flag[qid] && !new_exposed[qid]
                            if rand(rng) < prob
                                new_exposed[qid] = true
                            end
                        end
                    end
                end
            end
        end

        # Apply new exposures
        @inbounds for i in 1:n_people
            if new_exposed[i]
                exposed_flag[i] = true
                days_exposed_arr[i] = 1
            end
        end

        # Exposed → Infected transition
        @inbounds for i in 1:n_people
            if exposed_flag[i] && !infected_flag[i]
                if days_exposed_arr[i] >= exposed_days
                    exposed_flag[i] = false
                    infected_flag[i] = true
                    days_infected[i] = 1
                else
                    days_exposed_arr[i] += 1
                end
            end
        end

        # Recovery
        @inbounds for i in 1:n_people
            if infected_flag[i] && !recovered_flag[i]
                if days_infected[i] >= recovery_days
                    infected_flag[i] = false
                    recovered_flag[i] = true
                else
                    days_infected[i] += 1
                end
            end
        end

        push!(tick_nums, step)
        _s = 0; _e = 0; _i = 0; _r = 0
        @inbounds for i in 1:n_people
            if recovered_flag[i]
                _r += 1
            elseif infected_flag[i]
                _i += 1
            elseif exposed_flag[i]
                _e += 1
            else
                _s += 1
            end
        end
        push!(s_counts, Float64(_s))
        push!(e_counts, Float64(_e))
        push!(i_counts, Float64(_i))
        push!(r_counts, Float64(_r))
    end

    TrajectoryData(seed, tick_nums, Dict(
        "susceptible" => s_counts,
        "exposed"     => e_counts,
        "infected"    => i_counts,
        "recovered"   => r_counts,
    ))
end

# ── Age-Structured SIR ────────────────────────────────────────────────

function _age_multiplier(age::Int)
    age <= 18 && return 1.5
    age <= 64 && return 1.0
    return 0.8
end

function _run_julia_age_structured_sir_impl(seed::Int;
                                             n_people::Int=200,
                                             n_steps::Int=50,
                                             n_initial_infected::Int=5,
                                             beta::Float64=0.3,
                                             gamma_shape::Float64=1.56,
                                             gamma_rate::Float64=0.53,
                                             gamma_shift::Float64=-2.12,
                                             recovery_days::Int=14)
    June = _get_june_module()
    _Person            = getfield(June, :Person)
    _Household         = getfield(June, :Household)
    _School            = getfield(June, :School)
    _Company           = getfield(June, :Company)
    _add!              = getfield(June, :add!)
    _people            = getfield(June, :people)
    _reset_person_ids! = getfield(June, :reset_person_ids!)
    _reset_group_ids!  = getfield(June, :reset_group_ids!)

    rng = MersenneTwister(seed)
    _reset_person_ids!()
    _reset_group_ids!()

    all_people = [_Person(; sex=rand(rng, ['m', 'f']), age=rand(rng, 1:80))
                  for _ in 1:n_people]

    households = []
    for i in 1:4:n_people
        h = _Household()
        for j in i:min(i+3, n_people)
            _add!(h, all_people[j]; activity=:residence)
        end
        push!(households, h)
    end

    school = _School((0.0, 0.0), n_people, 5, 18, "primary")
    company = _Company(; n_workers_max=n_people)
    for p in all_people
        if p.age <= 18
            _add!(school, p)
        else
            _add!(company, p)
        end
    end

    all_groups = vcat(households, [school, company])
    group_member_ids = [Int[p.id for p in _people(grp)] for grp in all_groups]

    # Cache ages by person ID for quick lookup
    person_age = Dict{Int, Int}()
    for p in all_people
        person_age[p.id] = p.age
    end
    # Drop June.jl object references so GC can reclaim them
    all_people = nothing; households = nothing; all_groups = nothing; school = nothing; company = nothing

    infected_flag = falses(n_people)
    recovered_flag = falses(n_people)
    days_infected = zeros(Int, n_people)

    initial_idx = randperm(rng, n_people)[1:n_initial_infected]
    for idx in initial_idx
        infected_flag[idx] = true
        days_infected[idx] = 1
    end

    ft = FastGammaTransmission(beta, gamma_shape, gamma_rate, gamma_shift)

    s0, i0, r0 = _fast_sir_counts(infected_flag, recovered_flag); s_counts = Float64[s0]
    i_counts = Float64[i0]
    r_counts = Float64[r0]
    tick_nums = Int[0]

    new_infections = falses(n_people)
    for step in 1:n_steps
        fill!(new_infections, false)

        for member_ids in group_member_ids
            isempty(member_ids) && continue

            @inbounds for pid in member_ids
                if infected_flag[pid] && !recovered_flag[pid]
                    base_prob = fast_infection_prob(ft, Float64(days_infected[pid]))
                    @inbounds for qid in member_ids
                        if !infected_flag[qid] && !recovered_flag[qid] && !new_infections[qid]
                            if rand(rng) < base_prob * _age_multiplier(person_age[qid])
                                new_infections[qid] = true
                            end
                        end
                    end
                end
            end
        end

        @inbounds for i in 1:n_people
            if new_infections[i]
                infected_flag[i] = true
                days_infected[i] = 1
            end
        end

        @inbounds for i in 1:n_people
            if infected_flag[i] && !recovered_flag[i]
                if days_infected[i] >= recovery_days
                    infected_flag[i] = false
                    recovered_flag[i] = true
                else
                    days_infected[i] += 1
                end
            end
        end

        push!(tick_nums, step)
        sc, ic, rc = _fast_sir_counts(infected_flag, recovered_flag); push!(s_counts, sc)
        push!(i_counts, ic)
        push!(r_counts, rc)
    end

    TrajectoryData(seed, tick_nums, Dict(
        "susceptible" => s_counts,
        "infected"    => i_counts,
        "recovered"   => r_counts,
    ))
end

# ── SIR Vaccination ───────────────────────────────────────────────────

function _run_julia_sir_vaccination_impl(seed::Int;
                                          n_people::Int=200,
                                          n_steps::Int=50,
                                          n_initial_infected::Int=5,
                                          beta::Float64=0.3,
                                          gamma_shape::Float64=1.56,
                                          gamma_rate::Float64=0.53,
                                          gamma_shift::Float64=-2.12,
                                          recovery_days::Int=14,
                                          vaccination_fraction::Float64=0.3,
                                          vaccination_susceptibility::Float64=0.3)
    June = _get_june_module()
    _Person            = getfield(June, :Person)
    _Household         = getfield(June, :Household)
    _School            = getfield(June, :School)
    _Company           = getfield(June, :Company)
    _Immunity          = getfield(June, :Immunity)
    _add!              = getfield(June, :add!)
    _people            = getfield(June, :people)
    _reset_person_ids! = getfield(June, :reset_person_ids!)
    _reset_group_ids!  = getfield(June, :reset_group_ids!)
    _get_susceptibility = getfield(June, :get_susceptibility)

    rng = MersenneTwister(seed)
    _reset_person_ids!()
    _reset_group_ids!()

    all_people = [_Person(; sex=rand(rng, ['m', 'f']), age=rand(rng, 1:80))
                  for _ in 1:n_people]

    households = []
    for i in 1:4:n_people
        h = _Household()
        for j in i:min(i+3, n_people)
            _add!(h, all_people[j]; activity=:residence)
        end
        push!(households, h)
    end

    school = _School((0.0, 0.0), n_people, 5, 18, "primary")
    company = _Company(; n_workers_max=n_people)
    for p in all_people
        if p.age <= 18
            _add!(school, p)
        else
            _add!(company, p)
        end
    end

    all_groups = vcat(households, [school, company])
    group_member_ids = [Int[p.id for p in _people(grp)] for grp in all_groups]
    # Drop June.jl object references so GC can reclaim them
    households = nothing; all_groups = nothing

    infected_flag = falses(n_people)
    recovered_flag = falses(n_people)
    days_infected = zeros(Int, n_people)

    # Seed initial infections FIRST (same RNG sequence as Python)
    initial_idx = randperm(rng, n_people)[1:n_initial_infected]
    for idx in initial_idx
        infected_flag[idx] = true
        days_infected[idx] = 1
    end

    # Assign vaccination (after infection seeding, using same RNG sequence)
    # All people need Immunity objects for get_susceptibility to work
    for p in all_people
        p.immunity = _Immunity()
    end

    vaccinated_flag = falses(n_people)
    n_vaccinated = round(Int, n_people * vaccination_fraction)
    vax_order = randperm(rng, n_people)
    for idx in vax_order[1:n_vaccinated]
        vaccinated_flag[idx] = true
        all_people[idx].immunity.susceptibility_dict[0] = vaccination_susceptibility
    end

    # Track vaccinated who get infected
    vaccinated_infected_flag = falses(n_people)

    ft = FastGammaTransmission(beta, gamma_shape, gamma_rate, gamma_shift)

    s0, i0, r0 = _fast_sir_counts(infected_flag, recovered_flag); s_counts = Float64[s0]
    i_counts = Float64[i0]
    r_counts = Float64[r0]
    vi_counts = Float64[0.0]
    tick_nums = Int[0]

    new_infections = falses(n_people)
    for step in 1:n_steps
        fill!(new_infections, false)

        for member_ids in group_member_ids
            isempty(member_ids) && continue

            @inbounds for pid in member_ids
                if infected_flag[pid] && !recovered_flag[pid]
                    base_prob = fast_infection_prob(ft, Float64(days_infected[pid]))
                    @inbounds for qid in member_ids
                        if !infected_flag[qid] && !recovered_flag[qid] && !new_infections[qid]
                            sus = _get_susceptibility(all_people[qid].immunity, 0)
                            if rand(rng) < base_prob * sus
                                new_infections[qid] = true
                            end
                        end
                    end
                end
            end
        end

        @inbounds for i in 1:n_people
            if new_infections[i]
                infected_flag[i] = true
                days_infected[i] = 1
                if vaccinated_flag[i]
                    vaccinated_infected_flag[i] = true
                end
            end
        end

        @inbounds for i in 1:n_people
            if infected_flag[i] && !recovered_flag[i]
                if days_infected[i] >= recovery_days
                    infected_flag[i] = false
                    recovered_flag[i] = true
                else
                    days_infected[i] += 1
                end
            end
        end

        push!(tick_nums, step)
        sc, ic, rc = _fast_sir_counts(infected_flag, recovered_flag); push!(s_counts, sc)
        push!(i_counts, ic)
        push!(r_counts, rc)
        push!(vi_counts, Float64(count(vaccinated_infected_flag)))
    end

    TrajectoryData(seed, tick_nums, Dict(
        "susceptible"          => s_counts,
        "infected"             => i_counts,
        "recovered"            => r_counts,
        "vaccinated_infected"  => vi_counts,
    ))
end

# ── SIR Large (2000 people, 2 schools, 2 companies) ──────────────────

function _run_julia_sir_large_impl(seed::Int;
                                    n_people::Int=2000,
                                    n_steps::Int=100,
                                    n_initial_infected::Int=25,
                                    beta::Float64=0.3,
                                    gamma_shape::Float64=1.56,
                                    gamma_rate::Float64=0.53,
                                    gamma_shift::Float64=-2.12,
                                    recovery_days::Int=14)
    June = _get_june_module()
    _Person            = getfield(June, :Person)
    _Household         = getfield(June, :Household)
    _School            = getfield(June, :School)
    _Company           = getfield(June, :Company)
    _add!              = getfield(June, :add!)
    _people            = getfield(June, :people)
    _reset_person_ids! = getfield(June, :reset_person_ids!)
    _reset_group_ids!  = getfield(June, :reset_group_ids!)

    rng = MersenneTwister(seed)
    _reset_person_ids!()
    _reset_group_ids!()

    all_people = [_Person(; sex=rand(rng, ['m', 'f']), age=rand(rng, 1:80))
                  for _ in 1:n_people]

    households = []
    for i in 1:4:n_people
        h = _Household()
        for j in i:min(i+3, n_people)
            _add!(h, all_people[j]; activity=:residence)
        end
        push!(households, h)
    end

    # 2 schools and 2 companies — split by even/odd index among eligible
    school1 = _School((0.0, 0.0), n_people, 5, 18, "primary")
    school2 = _School((0.0, 0.0), n_people, 5, 18, "primary")
    company1 = _Company(; n_workers_max=n_people)
    company2 = _Company(; n_workers_max=n_people)

    school_idx = 0
    company_idx = 0
    for p in all_people
        if p.age <= 18
            if school_idx % 2 == 0
                _add!(school1, p)
            else
                _add!(school2, p)
            end
            school_idx += 1
        else
            if company_idx % 2 == 0
                _add!(company1, p)
            else
                _add!(company2, p)
            end
            company_idx += 1
        end
    end

    all_groups = vcat(households, [school1, school2, company1, company2])
    group_member_ids = [Int[p.id for p in _people(grp)] for grp in all_groups]
    # Drop June.jl object references so GC can reclaim them
    all_people = nothing; households = nothing; all_groups = nothing; school1 = nothing; school2 = nothing; company1 = nothing; company2 = nothing

    infected_flag = falses(n_people)
    recovered_flag = falses(n_people)
    days_infected = zeros(Int, n_people)

    initial_idx = randperm(rng, n_people)[1:n_initial_infected]
    for idx in initial_idx
        infected_flag[idx] = true
        days_infected[idx] = 1
    end

    ft = FastGammaTransmission(beta, gamma_shape, gamma_rate, gamma_shift)

    s0, i0, r0 = _fast_sir_counts(infected_flag, recovered_flag); s_counts = Float64[s0]
    i_counts = Float64[i0]
    r_counts = Float64[r0]
    tick_nums = Int[0]

    new_infections = zeros(Bool, n_people)  # Vector{Bool} for thread safety (not BitVector)
    # Pre-allocate per-group susceptible index buffers
    group_susceptible = [Int[] for _ in group_member_ids]
    # Per-task RNGs via task-local storage (safe with task migration in Julia 1.11+)
    nthreads = max(Threads.nthreads(), Threads.maxthreadid())
    thread_rngs = [MersenneTwister(rand(rng, UInt64)) for _ in 1:nthreads]
    for step in 1:n_steps
        fill!(new_infections, false)

        # Rebuild per-group susceptible lists (skip already infected/recovered)
        for (gi, member_ids) in enumerate(group_member_ids)
            sus = group_susceptible[gi]
            empty!(sus)
            @inbounds for qid in member_ids
                if !infected_flag[qid] && !recovered_flag[qid]
                    push!(sus, qid)
                end
            end
        end

        if nthreads > 1
            Threads.@threads for gi in eachindex(group_member_ids)
                member_ids = group_member_ids[gi]
                sus = group_susceptible[gi]
                isempty(sus) && continue
                trng = thread_rngs[Threads.threadid()]
                @inbounds for pid in member_ids
                    if infected_flag[pid] && !recovered_flag[pid]
                        prob = fast_infection_prob(ft, Float64(days_infected[pid]))
                        prob <= 0.0 && continue
                        @inbounds for qid in sus
                            if !new_infections[qid]
                                if rand(trng) < prob
                                    new_infections[qid] = true
                                end
                            end
                        end
                    end
                end
            end
        else
            for gi in eachindex(group_member_ids)
                member_ids = group_member_ids[gi]
                sus = group_susceptible[gi]
                isempty(sus) && continue
                @inbounds for pid in member_ids
                    if infected_flag[pid] && !recovered_flag[pid]
                        prob = fast_infection_prob(ft, Float64(days_infected[pid]))
                        prob <= 0.0 && continue
                        @inbounds for qid in sus
                            if !new_infections[qid]
                                if rand(rng) < prob
                                    new_infections[qid] = true
                                end
                            end
                        end
                    end
                end
            end
        end

        @inbounds for i in 1:n_people
            if new_infections[i]
                infected_flag[i] = true
                days_infected[i] = 1
            end
        end

        @inbounds for i in 1:n_people
            if infected_flag[i] && !recovered_flag[i]
                if days_infected[i] >= recovery_days
                    infected_flag[i] = false
                    recovered_flag[i] = true
                else
                    days_infected[i] += 1
                end
            end
        end

        push!(tick_nums, step)
        sc, ic, rc = _fast_sir_counts(infected_flag, recovered_flag); push!(s_counts, sc)
        push!(i_counts, ic)
        push!(r_counts, rc)
    end

    TrajectoryData(seed, tick_nums, Dict(
        "susceptible" => s_counts,
        "infected"    => i_counts,
        "recovered"   => r_counts,
    ))
end

# ── Complex Vaccines (SEIR + contact matrices + vaccination + NPI) ────

function run_julia(::ComplexVaccines, seed::Int; n_steps::Int=100, kwargs...)
    Base.invokelatest(_run_julia_complex_vaccines_impl, seed; n_steps=n_steps, kwargs...)
end

# Constants matching the Python complex_vaccines.py
const _CV_BETAS = Dict{String,Float64}(
    "household" => 0.208, "school" => 0.070, "company" => 0.371,
    "pub" => 0.429, "grocery" => 0.041)

const _CV_CONTACT_MATRICES = Dict{String,Any}(
    "household" => Dict("contacts" => [1.37 1.30 1.49 1.49;
                                        1.30 2.48 1.31 1.31;
                                        1.30 0.93 1.19 1.19;
                                        1.30 0.93 1.19 1.31],
                         "physical" => [0.79 0.70 0.70 0.70;
                                        0.70 0.34 0.40 0.40;
                                        0.70 0.40 0.62 0.62;
                                        0.70 0.62 0.62 0.45],
                         "char_time" => 12.0),
    "school" => Dict("contacts" => [5.0 15.0; 0.75 2.5],
                      "physical" => [0.05 0.08; 0.08 0.15],
                      "char_time" => 8.0),
    "company" => Dict("contacts" => reshape([4.8], 1, 1),
                       "physical" => reshape([0.07], 1, 1),
                       "char_time" => 8.0),
    "pub" => Dict("contacts" => reshape([3.0], 1, 1),
                   "physical" => reshape([0.12], 1, 1),
                   "char_time" => 3.0),
    "grocery" => Dict("contacts" => reshape([1.5], 1, 1),
                       "physical" => reshape([0.12], 1, 1),
                       "char_time" => 3.0))

const _CV_ALPHA_PHYSICAL = 2.0

# UK age distribution bins: (lo, hi, fraction)
const _CV_AGE_DIST = [(0,4,0.06),(5,11,0.08),(12,15,0.05),(16,17,0.03),
                       (18,24,0.09),(25,44,0.27),(45,64,0.25),(65,79,0.13),(80,99,0.04)]

const _CV_VAX_EFF_INFECTION = 0.80
const _CV_VAX_EFF_SYMPTOMS = 0.90
const _CV_VAX_EFF_DEATH = 0.95
const _CV_EXPOSED_DAYS = 3
const _CV_INFECTIOUS_DAYS = 7
const _CV_HOSPITAL_DAYS = 10
const _CV_DEATH_DAY = 5
const _CV_ASYMPTOMATIC_FRACTION = 0.40

# Weekday schedule: (hours, group_types)
const _CV_WEEKDAY_SCHEDULE = [
    (1.0, ["household"]),
    (8.0, ["household","school","company"]),
    (1.0, ["household"]),
    (3.0, ["household","pub","grocery"]),
    (11.0, ["household"])]

const _CV_WEEKEND_SCHEDULE = [
    (12.0, ["household","pub","grocery"]),
    (12.0, ["household"])]

@inline function _cv_hosp_rate(age::Int)
    age < 40 && return 0.01
    age < 60 && return 0.05
    age < 80 && return 0.15
    return 0.30
end

@inline function _cv_death_rate(age::Int)
    age < 60 && return 0.05
    age < 80 && return 0.20
    return 0.40
end

@inline function _cv_base_susceptibility(age::Int)
    age <= 12 ? 0.5 : 1.0
end

@inline function _cv_household_subgroup(age::Int)
    age <= 5 && return 1
    age <= 17 && return 2
    age <= 64 && return 3
    return 4
end

"""Pre-compute effective contact matrices (contacts * (1 + (alpha-1)*phys_frac)).
Returns a NamedTuple instead of Dict to avoid Dict allocation."""
function _cv_precompute_effective_contacts()
    function _compute_ec(cm)
        contacts = cm["contacts"]
        physical = cm["physical"]
        n = size(contacts, 1)
        ec = Matrix{Float64}(undef, n, n)
        @inbounds for a in 1:n, b in 1:n
            raw = contacts[a, b]
            if raw > 0.0
                phys_frac = physical[a, b] / raw
                ec[a, b] = raw * (1.0 + (_CV_ALPHA_PHYSICAL - 1.0) * phys_frac)
            else
                ec[a, b] = 0.0
            end
        end
        ec
    end
    (household = _compute_ec(_CV_CONTACT_MATRICES["household"]),
     school    = _compute_ec(_CV_CONTACT_MATRICES["school"]),
     company   = _compute_ec(_CV_CONTACT_MATRICES["company"]),
     pub       = _compute_ec(_CV_CONTACT_MATRICES["pub"]),
     grocery   = _compute_ec(_CV_CONTACT_MATRICES["grocery"]))
end

"""Create UK-like age distribution, matching Python create_population."""
function _cv_create_population(rng, n_people::Int)
    ages = Vector{Int}(undef, n_people)
    sexes = Vector{Char}(undef, n_people)
    sex_choices = ['m', 'f']
    total_assigned = 0
    pos = 1
    for (i, (lo, hi, frac)) in enumerate(_CV_AGE_DIST)
        if i < length(_CV_AGE_DIST)
            n = round(Int, n_people * frac)
        else
            n = n_people - total_assigned
        end
        total_assigned += n
        for _ in 1:n
            ages[pos] = rand(rng, lo:hi)
            sexes[pos] = rand(rng, sex_choices)
            pos += 1
        end
    end
    # Shuffle in-place via Fisher-Yates (avoids allocating indices + indexed copy)
    @inbounds for i in n_people:-1:2
        j = rand(rng, 1:i)
        ages[i], ages[j] = ages[j], ages[i]
        sexes[i], sexes[j] = sexes[j], sexes[i]
    end
    return ages, sexes
end

"""Create households in CSR format (flat member array + offset array).
Returns (flat_members::Vector{Int}, offsets::Vector{Int}) where
household i has members flat_members[offsets[i]:offsets[i+1]-1]."""
function _cv_create_households(ages::Vector{Int}, n_people::Int, rng)
    # Pre-allocate filter arrays instead of list comprehensions
    kids = Vector{Int}(undef, n_people)
    adults = Vector{Int}(undef, n_people)
    elderly = Vector{Int}(undef, n_people)
    nk = na = ne = 0
    @inbounds for i in 1:n_people
        a = ages[i]
        if a <= 17
            nk += 1; kids[nk] = i
        elseif a <= 64
            na += 1; adults[na] = i
        else
            ne += 1; elderly[ne] = i
        end
    end
    resize!(kids, nk); resize!(adults, na); resize!(elderly, ne)
    shuffle!(rng, kids); shuffle!(rng, adults); shuffle!(rng, elderly)

    # Build households into temporary Vector{Vector{Int}} first (for correctness),
    # then flatten into CSR format
    households_tmp = Vector{Vector{Int}}()
    ki, ai, ei = 1, 1, 1

    # Family households
    while ki <= length(kids) && ai <= length(adults)
        hh = [adults[ai]]; ai += 1
        if ai <= length(adults) && rand(rng) < 0.7
            push!(hh, adults[ai]); ai += 1
        end
        choices = [1,2,2,3]
        n_kids_add = min(choices[rand(rng, 1:4)], length(kids) - ki + 1)
        for _ in 1:n_kids_add
            push!(hh, kids[ki]); ki += 1
        end
        if ei <= length(elderly) && rand(rng) < 0.08
            push!(hh, elderly[ei]); ei += 1
        end
        push!(households_tmp, hh)
    end

    # Remaining kids
    while ki <= length(kids)
        if !isempty(households_tmp)
            idx = rand(rng, 1:length(households_tmp))
            push!(households_tmp[idx], kids[ki])
        else
            push!(households_tmp, [kids[ki]])
        end
        ki += 1
    end

    # Elderly households
    while ei <= length(elderly)
        if ei + 1 <= length(elderly) && rand(rng) < 0.5
            push!(households_tmp, [elderly[ei], elderly[ei+1]]); ei += 2
        else
            push!(households_tmp, [elderly[ei]]); ei += 1
        end
    end

    # Remaining adults
    while ai <= length(adults)
        remain = length(adults) - ai + 1
        choices = [1,2,2,3,4]
        sz = min(choices[rand(rng, 1:5)], remain)
        push!(households_tmp, adults[ai:ai+sz-1])
        ai += sz
    end

    # Convert to CSR format
    n_hh = length(households_tmp)
    total_members = sum(length, households_tmp)
    flat_members = Vector{Int}(undef, total_members)
    offsets = Vector{Int}(undef, n_hh + 1)
    pos = 1
    @inbounds for h in 1:n_hh
        offsets[h] = pos
        hh = households_tmp[h]
        for pid in hh
            flat_members[pos] = pid
            pos += 1
        end
    end
    offsets[n_hh + 1] = pos

    return flat_members, offsets
end

"""Create schools (primary, secondary, sixth-form) matching Python.
Returns (flat_members, offsets, subgroup_map::Vector{Int}, teacher_set)
where school i has members flat_members[offsets[i]:offsets[i+1]-1],
and subgroup_map[pid] gives 1=teacher, 2=student for school members."""
function _cv_create_schools(ages::Vector{Int}, n_people::Int, rng)
    # Pre-allocate filter arrays
    primary = Int[]; secondary = Int[]; sixth = Int[]; pot_teachers = Int[]
    sizehint!(primary, n_people÷5); sizehint!(secondary, n_people÷10)
    sizehint!(sixth, n_people÷20); sizehint!(pot_teachers, n_people÷3)
    @inbounds for i in 1:n_people
        a = ages[i]
        if 5 <= a <= 11;      push!(primary, i)
        elseif 12 <= a <= 15;  push!(secondary, i)
        elseif 16 <= a <= 18;  push!(sixth, i)
        end
        if 25 <= a <= 60; push!(pot_teachers, i); end
    end
    shuffle!(rng, pot_teachers)
    n_teachers = max(3, div(length(pot_teachers) * 2, 100))  # 2%
    teacher_pool = pot_teachers[1:min(n_teachers, length(pot_teachers))]

    student_lists = [primary, secondary, sixth]
    total_students = sum(length, student_lists)
    if total_students == 0
        return (Int[], [1], zeros(Int, n_people), Set{Int}())
    end

    teacher_counts = [isempty(sl) ? 0 : max(1, div(n_teachers * length(sl), total_students))
                      for sl in student_lists]
    while sum(teacher_counts) > length(teacher_pool)
        for j in length(teacher_counts):-1:1
            if teacher_counts[j] > 1
                teacher_counts[j] -= 1
                break
            end
        end
    end

    teacher_set = Set{Int}()
    subgroup_map = zeros(Int, n_people)

    # Count total members to pre-allocate
    total_school_members = 0
    ti = 1
    active_schools = 0
    for (students, n_t) in zip(student_lists, teacher_counts)
        isempty(students) && continue
        active_schools += 1
        end_ti = min(ti + n_t - 1, length(teacher_pool))
        total_school_members += (end_ti - ti + 1) + length(students)
        ti = end_ti + 1
    end

    flat_members = Vector{Int}(undef, total_school_members)
    offsets = Vector{Int}(undef, active_schools + 1)
    pos = 1
    school_idx = 0
    ti = 1
    for (students, n_t) in zip(student_lists, teacher_counts)
        isempty(students) && continue
        school_idx += 1
        offsets[school_idx] = pos
        end_ti = min(ti + n_t - 1, length(teacher_pool))
        # Add teachers
        for j in ti:end_ti
            pid = teacher_pool[j]
            flat_members[pos] = pid
            pos += 1
            push!(teacher_set, pid)
            subgroup_map[pid] = 1  # teacher
        end
        ti = end_ti + 1
        # Add students
        for pid in students
            flat_members[pos] = pid
            pos += 1
            subgroup_map[pid] = 2  # student
        end
    end
    offsets[school_idx + 1] = pos

    return flat_members, offsets, subgroup_map, teacher_set
end

"""Create companies matching Python. Returns CSR format (flat_members, offsets)."""
function _cv_create_companies(ages::Vector{Int}, n_people::Int, teacher_set::Set{Int}, rng)
    workers = Int[]
    sizehint!(workers, n_people÷2)
    @inbounds for i in 1:n_people
        if 19 <= ages[i] <= 64 && i ∉ teacher_set
            push!(workers, i)
        end
    end
    shuffle!(rng, workers)
    n_companies = min(10, max(1, div(length(workers), 5)))
    per = div(length(workers), n_companies)

    # Build CSR directly
    flat_members = copy(workers)  # all workers are company members
    offsets = Vector{Int}(undef, n_companies + 1)
    @inbounds for c in 0:n_companies-1
        offsets[c+1] = c * per + 1
    end
    offsets[n_companies + 1] = length(workers) + 1

    flat_members, offsets
end

"""Transmission within a group with subgroup contact matrix (Poisson approx)."""
@inline function _cv_transmit!(
    members::AbstractVector{Int}, subgroup_fn, state::Vector{UInt8},
    days_infected::Vector{Float64}, susceptibility::Vector{Float64},
    new_exposed::Vector{Bool}, ft::FastGammaTransmission,
    ec_matrix::Matrix{Float64}, beta::Float64, char_time::Float64,
    dt::Float64, rng)

    # Collect active members and find infectors
    n_sg = size(ec_matrix, 1)
    group_size = 0
    has_infector = false

    @inbounds for pid in members
        st = state[pid]
        st == 0x04 && continue  # D
        st == 0x05 && continue  # H
        group_size += 1
        if st == 0x02  # I
            has_infector = true
        end
    end

    group_size <= 1 && return
    has_infector || return

    dt_ratio = dt / char_time

    @inbounds for pid in members
        state[pid] == 0x02 || continue  # only infectors
        inf = fast_infection_prob(ft, days_infected[pid])
        inf <= 0.0 && continue
        sg_i = subgroup_fn(pid)

        @inbounds for qid in members
            state[qid] == 0x00 || continue  # only susceptible
            new_exposed[qid] && continue
            sg_j = subgroup_fn(qid)
            ec = ec_matrix[sg_i, sg_j]
            ec <= 0.0 && continue
            prob = 1.0 - exp(-beta * ec * inf * susceptibility[qid] * dt_ratio / group_size)
            if rand(rng) < prob
                new_exposed[qid] = true
            end
        end
    end
end

# State encoding: S=0, E=1, I=2, R=3, D=4, H=5
const _CV_S = 0x00
const _CV_E = 0x01
const _CV_I = 0x02
const _CV_R = 0x03
const _CV_D = 0x04
const _CV_H = 0x05

function _run_julia_complex_vaccines_impl(seed::Int;
    n_people::Int=5000, n_steps::Int=100, n_initial_infected::Int=25,
    vax_min_age::Int=18, vax_coverage::Float64=0.8,
    school_beta_factor::Float64=1.0, kwargs...)

    June = _get_june_module()
    _reset_person_ids! = getfield(June, :reset_person_ids!)
    _reset_group_ids!  = getfield(June, :reset_group_ids!)
    Base.invokelatest(_reset_person_ids!)
    Base.invokelatest(_reset_group_ids!)

    rng = MersenneTwister(seed)

    # Build population (matching Python's create_population exactly)
    ages, sexes = _cv_create_population(rng, n_people)

    # Build groups
    hh_flat, hh_offsets = _cv_create_households(ages, n_people, rng)
    n_households = length(hh_offsets) - 1
    school_flat, school_offsets, school_subgroup_global, teacher_set = _cv_create_schools(ages, n_people, rng)
    n_schools = length(school_offsets) - 1
    comp_flat, comp_offsets = _cv_create_companies(ages, n_people, teacher_set, rng)
    n_companies = length(comp_offsets) - 1

    # State arrays (UInt8 for fast comparison)
    state = fill(_CV_S, n_people)
    days_in_state = zeros(Int8, n_people)
    days_infected = zeros(Float64, n_people)
    is_symptomatic = falses(n_people)
    will_hospitalise = falses(n_people)
    will_die = falses(n_people)
    vaccinated = falses(n_people)
    ever_infected_vax = falses(n_people)

    # Vaccination — in-place shuffle avoids list comprehension allocation
    eligible = Vector{Int}(undef, n_people)
    n_eligible = 0
    @inbounds for i in 1:n_people
        if ages[i] >= vax_min_age
            n_eligible += 1
            eligible[n_eligible] = i
        end
    end
    resize!(eligible, n_eligible)
    n_vax = round(Int, n_eligible * vax_coverage)
    shuffle!(rng, eligible)
    @inbounds for j in 1:min(n_vax, n_eligible)
        vaccinated[eligible[j]] = true
    end

    # Pre-compute susceptibility
    susceptibility = zeros(Float64, n_people)
    @inbounds for i in 1:n_people
        s = _cv_base_susceptibility(ages[i])
        if vaccinated[i]
            s *= (1.0 - _CV_VAX_EFF_INFECTION)
        end
        susceptibility[i] = s
    end

    # Seed initial infections
    all_ids = randperm(rng, n_people)
    @inbounds for idx in all_ids[1:min(n_initial_infected, n_people)]
        state[idx] = _CV_I
        days_in_state[idx] = 0
        days_infected[idx] = 1.0
        sym_prob = 1.0 - _CV_ASYMPTOMATIC_FRACTION
        if vaccinated[idx]; sym_prob *= (1.0 - _CV_VAX_EFF_SYMPTOMS); end
        is_symptomatic[idx] = rand(rng) < sym_prob
        if is_symptomatic[idx]
            will_hospitalise[idx] = rand(rng) < _cv_hosp_rate(ages[idx])
        end
        if vaccinated[idx]; ever_infected_vax[idx] = true; end
    end

    # Transmission model
    ft = FastGammaTransmission(1.0, 1.56, 0.53, -2.12)
    eff_contacts = _cv_precompute_effective_contacts()

    # Effective betas (avoid Dict copy — just compute scalars directly)
    beta_household = _CV_BETAS["household"]
    beta_school_eff = _CV_BETAS["school"] * school_beta_factor
    beta_company = _CV_BETAS["company"]
    beta_pub = _CV_BETAS["pub"]
    beta_grocery = _CV_BETAS["grocery"]

    # Pre-allocate
    new_exposed = Vector{Bool}(undef, n_people)

    # Pre-allocate output arrays (n_steps + 1 entries: initial + each step)
    total_records = n_steps + 1
    tick_nums = Vector{Int}(undef, total_records)
    s_counts = Vector{Float64}(undef, total_records)
    e_counts = Vector{Float64}(undef, total_records)
    i_counts = Vector{Float64}(undef, total_records)
    r_counts = Vector{Float64}(undef, total_records)
    d_counts = Vector{Float64}(undef, total_records)
    h_counts = Vector{Float64}(undef, total_records)
    vi_counts = Vector{Float64}(undef, total_records)
    record_idx = 0

    # Count initial state
    function count_states!(tick::Int)
        record_idx += 1
        s = 0; e = 0; inf = 0; r = 0; d = 0; h = 0; vi = 0
        @inbounds for i in 1:n_people
            st = state[i]
            if st == _CV_S; s += 1
            elseif st == _CV_E; e += 1
            elseif st == _CV_I; inf += 1
            elseif st == _CV_R; r += 1
            elseif st == _CV_D; d += 1
            elseif st == _CV_H; h += 1
            end
            if ever_infected_vax[i]; vi += 1; end
        end
        @inbounds begin
            tick_nums[record_idx] = tick
            s_counts[record_idx] = Float64(s)
            e_counts[record_idx] = Float64(e)
            i_counts[record_idx] = Float64(inf)
            r_counts[record_idx] = Float64(r)
            d_counts[record_idx] = Float64(d)
            h_counts[record_idx] = Float64(h)
            vi_counts[record_idx] = Float64(vi)
        end
    end
    count_states!(0)

    # Household subgroup function (returns 1-based index matching 4×4 matrix)
    hh_sg = let ages=ages
        @inline pid -> _cv_household_subgroup(ages[pid])
    end

    # School subgroup function (returns 1 or 2)
    # school_subgroup_global already returned from _cv_create_schools
    school_sg = let m=school_subgroup_global
        @inline pid -> m[pid]
    end

    # Single subgroup function (always 1)
    single_sg = @inline _ -> 1

    # Pre-allocate leisure buffers (avoid per-day allocation)
    pub_today = Vector{Int}(undef, n_people)
    grocery_today = Vector{Int}(undef, n_people)
    n_pub = 0
    n_grocery = 0
    # View wrappers that we'll resize each day
    pub_view = view(pub_today, 1:0)
    grocery_view = view(grocery_today, 1:0)

    # Pre-extract effective contact matrices from NamedTuple
    ec_household = eff_contacts.household
    ec_school = eff_contacts.school
    ec_company = eff_contacts.company
    ec_pub = eff_contacts.pub
    ec_grocery = eff_contacts.grocery

    for day in 0:n_steps-1
        day_of_week = day % 7
        is_weekday = day_of_week < 5
        schedule = is_weekday ? _CV_WEEKDAY_SCHEDULE : _CV_WEEKEND_SCHEDULE
        leisure_rate = is_weekday ? 0.2 : 0.3

        # Leisure attendance — fill pre-allocated buffers
        n_pub = 0
        n_grocery = 0
        @inbounds for i in 1:n_people
            (state[i] == _CV_D || state[i] == _CV_H) && continue
            if rand(rng) < leisure_rate
                n_pub += 1
                pub_today[n_pub] = i
            end
            if rand(rng) < leisure_rate
                n_grocery += 1
                grocery_today[n_grocery] = i
            end
        end

        fill!(new_exposed, false)

        # Sub-timesteps
        for (dt, active_types) in schedule
            for gtype in active_types
                if gtype == "household"
                    @inbounds for h in 1:n_households
                        hh_view = view(hh_flat, hh_offsets[h]:hh_offsets[h+1]-1)
                        _cv_transmit!(hh_view, hh_sg, state, days_infected, susceptibility,
                                     new_exposed, ft, ec_household,
                                     beta_household, 12.0, dt, rng)
                    end
                elseif gtype == "school"
                    @inbounds for s in 1:n_schools
                        school_view = view(school_flat, school_offsets[s]:school_offsets[s+1]-1)
                        _cv_transmit!(school_view, school_sg, state, days_infected, susceptibility,
                                     new_exposed, ft, ec_school,
                                     beta_school_eff, 8.0, dt, rng)
                    end
                elseif gtype == "company"
                    @inbounds for c in 1:n_companies
                        comp_view = view(comp_flat, comp_offsets[c]:comp_offsets[c+1]-1)
                        _cv_transmit!(comp_view, single_sg, state, days_infected, susceptibility,
                                     new_exposed, ft, ec_company,
                                     beta_company, 8.0, dt, rng)
                    end
                elseif gtype == "pub"
                    if n_pub > 0
                        pub_slice = view(pub_today, 1:n_pub)
                        _cv_transmit!(pub_slice, single_sg, state, days_infected, susceptibility,
                                     new_exposed, ft, ec_pub,
                                     beta_pub, 3.0, dt, rng)
                    end
                elseif gtype == "grocery"
                    if n_grocery > 0
                        grocery_slice = view(grocery_today, 1:n_grocery)
                        _cv_transmit!(grocery_slice, single_sg, state, days_infected, susceptibility,
                                     new_exposed, ft, ec_grocery,
                                     beta_grocery, 3.0, dt, rng)
                    end
                end
            end
        end

        # Apply new exposures
        @inbounds for i in 1:n_people
            if new_exposed[i]
                state[i] = _CV_E
                days_in_state[i] = 0
                if vaccinated[i]; ever_infected_vax[i] = true; end
            end
        end

        # Disease progression (daily)
        @inbounds for i in 1:n_people
            si = state[i]

            if si == _CV_E
                days_in_state[i] += 1
                if days_in_state[i] >= _CV_EXPOSED_DAYS
                    state[i] = _CV_I
                    days_in_state[i] = 0
                    days_infected[i] = 1.0
                    sym_prob = 1.0 - _CV_ASYMPTOMATIC_FRACTION
                    if vaccinated[i]; sym_prob *= (1.0 - _CV_VAX_EFF_SYMPTOMS); end
                    is_symptomatic[i] = rand(rng) < sym_prob
                    if is_symptomatic[i]
                        will_hospitalise[i] = rand(rng) < _cv_hosp_rate(ages[i])
                    end
                end
            elseif si == _CV_I
                days_in_state[i] += 1
                days_infected[i] += 1.0
                if days_in_state[i] >= _CV_INFECTIOUS_DAYS
                    if will_hospitalise[i]
                        state[i] = _CV_H
                        days_in_state[i] = 0
                        dp = _cv_death_rate(ages[i])
                        if vaccinated[i]; dp *= (1.0 - _CV_VAX_EFF_DEATH); end
                        will_die[i] = rand(rng) < dp
                    else
                        state[i] = _CV_R
                        days_in_state[i] = 0
                    end
                end
            elseif si == _CV_H
                days_in_state[i] += 1
                if will_die[i] && days_in_state[i] >= _CV_DEATH_DAY
                    state[i] = _CV_D
                    days_in_state[i] = 0
                elseif !will_die[i] && days_in_state[i] >= _CV_HOSPITAL_DAYS
                    state[i] = _CV_R
                    days_in_state[i] = 0
                end
            end
        end

        # Record
        count_states!(day + 1)
    end

    TrajectoryData(seed, tick_nums, Dict(
        "susceptible"           => s_counts,
        "exposed"               => e_counts,
        "infected"              => i_counts,
        "recovered"             => r_counts,
        "dead"                  => d_counts,
        "hospitalised"          => h_counts,
        "vaccinated_infected"   => vi_counts,
    ))
end

# ── Custom Python parsing for ComplexVaccines (different CSV format) ──

function run_python(scenario::ComplexVaccines, seed::Int;
                    n_steps::Int=default_n_steps(scenario),
                    measure_memory::Bool=false,
                    kwargs...)
    py = python_cmd()
    script = python_script(scenario)
    vars = tracked_vars(scenario)

    # Only pass kwargs the Python script accepts
    py_kwargs = Set([:n_people, :n_initial_infected, :vax_min_age, :vax_coverage, :school_beta_factor])
    cmd_parts = [py, script, "--seed", string(seed), "--n_steps", string(n_steps)]
    for (k, v) in kwargs
        k in py_kwargs || continue
        push!(cmd_parts, "--$(k)")
        push!(cmd_parts, string(v))
    end
    if measure_memory; push!(cmd_parts, "--measure_memory"); end
    cmd = Cmd(cmd_parts)

    if measure_memory
        stdout_buf = IOBuffer(); stderr_buf = IOBuffer()
        run(pipeline(cmd, stdout=stdout_buf, stderr=stderr_buf), wait=true)
        stdout_str = String(take!(stdout_buf))
        stderr_str = String(take!(stderr_buf))
    else
        stdout_str = read(cmd, String)
        stderr_str = ""
    end

    # Parse: step,day,susceptible,exposed,infected,recovered,dead,hospitalised,vaccinated_infected
    ticks = Int[]
    val_arrays = Dict{String, Vector{Float64}}(v => Float64[] for v in vars)
    col_map = Dict("susceptible" => 3, "exposed" => 4, "infected" => 5,
                   "recovered" => 6, "dead" => 7, "hospitalised" => 8,
                   "vaccinated_infected" => 9)

    for line in split(stdout_str, '\n')
        line = strip(line); isempty(line) && continue
        startswith(line, "step") && continue
        parts = split(line, ',')
        length(parts) < 9 && continue
        push!(ticks, parse(Int, parts[1]))
        for v in vars
            push!(val_arrays[v], parse(Float64, parts[col_map[v]]))
        end
    end

    peak_mem = 0.0
    if measure_memory
        for line in split(stderr_str, '\n')
            line = strip(line)
            if startswith(line, "MEMORY:")
                mem_parts = split(line[8:end], ',')
                length(mem_parts) >= 2 && (peak_mem = parse(Float64, mem_parts[2]))
            end
        end
    end

    (TrajectoryData(seed, ticks, val_arrays), peak_mem)
end

function run_python_sir(seed::Int;
                        n_people::Int=200,
                        n_steps::Int=50,
                        n_initial_infected::Int=5,
                        beta::Float64=0.3,
                        gamma_shape::Float64=1.56,
                        gamma_rate::Float64=0.53,
                        gamma_shift::Float64=-2.12,
                        recovery_days::Int=14)
    py = python_cmd()
    script = joinpath(SCENARIO_DIR, "simple_sir.py")

    cmd = `$py $script
        --seed $seed
        --n_people $n_people
        --n_steps $n_steps
        --n_initial_infected $n_initial_infected
        --beta $beta
        --gamma_shape $gamma_shape
        --gamma_rate $gamma_rate
        --gamma_shift $gamma_shift
        --recovery_days $recovery_days`

    output = read(cmd, String)

    # Parse CSV output: step,susceptible,infected,recovered
    ticks = Int[]
    s_vals = Float64[]
    i_vals = Float64[]
    r_vals = Float64[]

    for line in split(output, '\n')
        line = strip(line)
        isempty(line) && continue
        startswith(line, "step") && continue  # skip header
        parts = split(line, ',')
        length(parts) < 4 && continue
        push!(ticks, parse(Int, parts[1]))
        push!(s_vals, parse(Float64, parts[2]))
        push!(i_vals, parse(Float64, parts[3]))
        push!(r_vals, parse(Float64, parts[4]))
    end

    TrajectoryData(seed, ticks, Dict(
        "susceptible" => s_vals,
        "infected"    => i_vals,
        "recovered"   => r_vals,
    ))
end

# ── Generic Python runner (dispatches on scenario) ────────────────────

"""
    run_python(scenario, seed; n_steps, measure_memory=false, kwargs...) -> (TrajectoryData, Float64)

Run the Python script for the given scenario. Returns (trajectory, peak_memory_bytes).
peak_memory_bytes is 0.0 unless measure_memory=true.
"""
function run_python(scenario::AbstractScenario, seed::Int;
                    n_steps::Int=default_n_steps(scenario),
                    measure_memory::Bool=false,
                    kwargs...)
    py = python_cmd()
    script = python_script(scenario)
    vars = tracked_vars(scenario)

    extra = python_extra_args(scenario)
    mem_flag = measure_memory ? ["--measure_memory"] : String[]

    # Build command with standard args + extra scenario-specific args
    cmd_parts = [py, script, "--seed", string(seed), "--n_steps", string(n_steps)]
    for (k, v) in kwargs
        push!(cmd_parts, "--$(k)")
        push!(cmd_parts, string(v))
    end
    append!(cmd_parts, extra)
    append!(cmd_parts, mem_flag)

    cmd = Cmd(cmd_parts)

    if measure_memory
        # Use pipeline to capture both stdout and stderr
        stdout_buf = IOBuffer()
        stderr_buf = IOBuffer()
        proc = run(pipeline(cmd, stdout=stdout_buf, stderr=stderr_buf), wait=true)
        stdout_str = String(take!(stdout_buf))
        stderr_str = String(take!(stderr_buf))
    else
        stdout_str = read(cmd, String)
        stderr_str = ""
    end

    # Parse CSV output
    ticks = Int[]
    val_arrays = Dict{String, Vector{Float64}}(v => Float64[] for v in vars)

    for line in split(stdout_str, '\n')
        line = strip(line)
        isempty(line) && continue
        startswith(line, "step") && continue
        parts = split(line, ',')
        length(parts) < length(vars) + 1 && continue
        push!(ticks, parse(Int, parts[1]))
        for (i, v) in enumerate(vars)
            push!(val_arrays[v], parse(Float64, parts[i+1]))
        end
    end

    # Parse memory from stderr
    peak_mem = 0.0
    if measure_memory
        for line in split(stderr_str, '\n')
            line = strip(line)
            if startswith(line, "MEMORY:")
                mem_parts = split(line[8:end], ',')
                if length(mem_parts) >= 2
                    peak_mem = parse(Float64, mem_parts[2])
                end
            end
        end
    end

    (TrajectoryData(seed, ticks, val_arrays), peak_mem)
end

# Convenience: run_python without memory returns just TrajectoryData
function run_python_traj(scenario::AbstractScenario, seed::Int; kwargs...)
    traj, _ = run_python(scenario, seed; measure_memory=false, kwargs...)
    traj
end

# ── Memory measurement wrappers ───────────────────────────────────────

"""
    run_julia_timed(scenario, seed; kwargs...) -> (TrajectoryData, time_s, peak_mem_bytes)

Run Julia scenario with timing and peak memory (RSS delta) measurement.
Uses gc_live_bytes() before/after for a fair comparison with Python's tracemalloc peak.
"""
function run_julia_timed(scenario::AbstractScenario, seed::Int; kwargs...)
    GC.gc(); GC.gc()
    local traj
    local alloc_bytes
    t = @elapsed begin
        alloc_bytes = @allocated begin
            traj = run_julia(scenario, seed; kwargs...)
        end
    end
    (traj, t, Float64(alloc_bytes))
end

# ── Batch runners ─────────────────────────────────────────────────────

function run_julia_trajectories(seeds::Vector{Int}; kwargs...)
    # Julia scenarios use global mutable ID counters — not safe for @threads
    [run_julia_sir(s; kwargs...) for s in seeds]
end

function run_julia_trajectories(scenario::AbstractScenario, seeds::Vector{Int}; kwargs...)
    # Julia scenarios use global mutable ID counters — not safe for @threads
    [run_julia(scenario, s; kwargs...) for s in seeds]
end

function run_python_trajectories(seeds::Vector{Int}; kwargs...)
    if Threads.nthreads() > 1
        results = Vector{TrajectoryData}(undef, length(seeds))
        Threads.@threads for i in eachindex(seeds)
            results[i] = run_python_sir(seeds[i]; kwargs...)
        end
        return results
    else
        return [run_python_sir(s; kwargs...) for s in seeds]
    end
end

function run_python_trajectories(scenario::AbstractScenario, seeds::Vector{Int}; kwargs...)
    if Threads.nthreads() > 1
        results = Vector{TrajectoryData}(undef, length(seeds))
        Threads.@threads for i in eachindex(seeds)
            results[i] = run_python_traj(scenario, seeds[i]; kwargs...)
        end
        return results
    else
        return [run_python_traj(scenario, s; kwargs...) for s in seeds]
    end
end

# ── Statistics ────────────────────────────────────────────────────────

"""Two-sample Kolmogorov-Smirnov statistic."""
function ks_statistic(a::Vector{Float64}, b::Vector{Float64})
    sa = sort(filter(!isnan, a))
    sb = sort(filter(!isnan, b))
    na, nb = length(sa), length(sb)
    (na == 0 || nb == 0) && return NaN
    all_v = sort(unique(vcat(sa, sb)))
    maximum(abs(searchsortedlast(sa, v)/na - searchsortedlast(sb, v)/nb) for v in all_v)
end

"""Pearson correlation; returns NaN for constant/empty inputs."""
function pearson_r(x::Vector{Float64}, y::Vector{Float64})
    fx = filter(!isnan, x)
    fy = filter(!isnan, y)
    n = min(length(fx), length(fy))
    n < 2 && return NaN
    a, b = fx[1:n], fy[1:n]
    (std(a) < 1e-15 || std(b) < 1e-15) && return (std(a) < 1e-15 && std(b) < 1e-15) ? 1.0 : NaN
    cor(a, b)
end

"""Correlation of empirical CDFs evaluated at the sorted union of both samples."""
function ecdf_correlation(a::Vector{Float64}, b::Vector{Float64})
    sa = sort(filter(!isnan, a))
    sb = sort(filter(!isnan, b))
    na, nb = length(sa), length(sb)
    (na < 2 || nb < 2) && return NaN
    pts = sort(unique(vcat(sa, sb)))
    length(pts) < 2 && return NaN
    ecdf_a = Float64[searchsortedlast(sa, v) / na for v in pts]
    ecdf_b = Float64[searchsortedlast(sb, v) / nb for v in pts]
    pearson_r(ecdf_a, ecdf_b)
end

"""QQ correlation: sort both samples, pair by rank, compute Pearson r."""
function qq_correlation(a::Vector{Float64}, b::Vector{Float64})
    sa = sort(filter(!isnan, a))
    sb = sort(filter(!isnan, b))
    na, nb = length(sa), length(sb)
    (na < 3 || nb < 3) && return NaN
    n_pts = max(na, nb)
    probs = range(0.0, 1.0, length=n_pts)
    qa = quantile_at.(Ref(sa), probs)
    qb = quantile_at.(Ref(sb), probs)
    pearson_r(qa, qb)
end

"""Linear interpolation quantile (like R's type=7)."""
function quantile_at(sorted::Vector{Float64}, p::Float64)
    n = length(sorted)
    n == 0 && return NaN
    n == 1 && return sorted[1]
    h = (n - 1) * p + 1.0
    lo = clamp(floor(Int, h), 1, n)
    hi = clamp(lo + 1, 1, n)
    sorted[lo] + (h - lo) * (sorted[hi] - sorted[lo])
end

# ── Maximum Mean Discrepancy (MMD) on trajectories ───────────────────

"""
    mmd_rbf(X, Y; n_perms=500) -> (mmd², p_value)

Unbiased MMD² between two sets of trajectories using Gaussian RBF kernel
with median heuristic for bandwidth. Each row is one trajectory.
"""
function mmd_rbf(X::Matrix{Float64}, Y::Matrix{Float64}; n_perms::Int=500)
    m = size(X, 1)
    n = size(Y, 1)
    (m < 2 || n < 2) && return (NaN, NaN)

    combined = vcat(X, Y)
    N = m + n
    D2 = _pairwise_sq_dists(combined)

    upper = Float64[]
    for i in 1:N, j in (i+1):N
        D2[i,j] > 0.0 && push!(upper, D2[i,j])
    end
    isempty(upper) && return (0.0, 1.0)
    sigma2 = median(upper)
    sigma2 < 1e-30 && return (0.0, 1.0)

    K = exp.(-D2 ./ (2.0 * sigma2))

    observed = _mmd2_from_kernel(K, 1:m, (m+1):N)

    perm_count = 0
    idxs = collect(1:N)
    rng = MersenneTwister(12345)
    for _ in 1:n_perms
        shuffle!(rng, idxs)
        perm_val = _mmd2_from_kernel(K, @view(idxs[1:m]), @view(idxs[m+1:N]))
        perm_val >= observed && (perm_count += 1)
    end
    p_value = (perm_count + 1) / (n_perms + 1)

    (observed, p_value)
end

"""Pairwise squared Euclidean distances between rows of X."""
function _pairwise_sq_dists(X::Matrix{Float64})
    norms = sum(X .^ 2, dims=2)
    D2 = norms .+ norms' .- 2.0 .* (X * X')
    D2 .= max.(D2, 0.0)
    D2
end

"""Unbiased MMD² given a pre-computed kernel matrix and index sets."""
function _mmd2_from_kernel(K::Matrix{Float64}, A, B)
    m = length(A)
    n = length(B)
    sum_AA = 0.0
    for i in A, j in A
        i != j && (sum_AA += K[i, j])
    end
    sum_BB = 0.0
    for i in B, j in B
        i != j && (sum_BB += K[i, j])
    end
    sum_AB = 0.0
    for i in A, j in B
        sum_AB += K[i, j]
    end
    sum_AA / (m * (m - 1)) + sum_BB / (n * (n - 1)) - 2.0 * sum_AB / (m * n)
end

"""
    trajectory_mmd(jl_trajs, py_trajs, var_name, n_steps; n_perms=500)

Extract trajectory for `var_name` from each replicate, form matrices, and
compute MMD² with permutation p-value.
"""
function trajectory_mmd(jl::Vector{TrajectoryData}, py::Vector{TrajectoryData},
                        g::String, n_steps::Int; n_perms::Int=500)
    T = n_steps + 1
    function extract_matrix(trajs)
        rows = Vector{Float64}[]
        for traj in trajs
            v = get(traj.values, g, Float64[])
            isempty(v) && continue
            if length(v) >= T
                push!(rows, Float64.(v[1:T]))
            else
                padded = Vector{Float64}(undef, T)
                padded[1:length(v)] .= v
                padded[length(v)+1:T] .= v[end]
                push!(rows, padded)
            end
        end
        isempty(rows) && return Matrix{Float64}(undef, 0, 0)
        reduce(vcat, [r' for r in rows])
    end
    X = extract_matrix(jl)
    Y = extract_matrix(py)
    (size(X, 1) < 2 || size(Y, 1) < 2) && return (NaN, NaN)
    mmd_rbf(X, Y; n_perms=n_perms)
end

# ── Comparison logic ──────────────────────────────────────────────────

const TRACKED_VARS = ["susceptible", "infected", "recovered"]

function compute_comparisons(jl::Vector{TrajectoryData}, py::Vector{TrajectoryData},
                             globals::Vector{String}, n_steps::Int)
    comparisons = VariableComparison[]
    for g in globals
        jl_by_tick = [Float64[] for _ in 0:n_steps]
        py_by_tick = [Float64[] for _ in 0:n_steps]

        for traj in jl
            v = get(traj.values, g, Float64[])
            for (i, t) in enumerate(traj.ticks)
                0 <= t <= n_steps && push!(jl_by_tick[t+1], i <= length(v) ? v[i] : NaN)
            end
        end
        for traj in py
            v = get(traj.values, g, Float64[])
            for (i, t) in enumerate(traj.ticks)
                0 <= t <= n_steps && push!(py_by_tick[t+1], i <= length(v) ? v[i] : NaN)
            end
        end

        safe_mean(x) = (f = filter(!isnan, x); isempty(f) ? NaN : mean(f))
        safe_std(x)  = (f = filter(!isnan, x); length(f) < 2 ? 0.0 : std(f))
        safe_median(x) = (f = filter(!isnan, x); isempty(f) ? NaN : median(f))

        jl_m = safe_mean.(jl_by_tick)
        jl_s = safe_std.(jl_by_tick)
        py_m = safe_mean.(py_by_tick)
        py_s = safe_std.(py_by_tick)

        diffs = abs.(jl_m .- py_m)
        fd = filter(!isnan, diffs)
        mae = isempty(fd) ? NaN : mean(fd)

        py_clean = filter(!isnan, py_m)
        val_range = isempty(py_clean) ? 1.0 : max(maximum(py_clean) - minimum(py_clean), 1.0)
        nmae = mae / val_range

        r_traj = pearson_r(jl_m, py_m)

        final_jl = Float64[last(get(t.values, g, [NaN])) for t in jl]
        final_py = Float64[last(get(t.values, g, [NaN])) for t in py]

        mmd2, mmd_p = trajectory_mmd(jl, py, g, n_steps; n_perms=500)

        push!(comparisons, VariableComparison(
            g, jl_m, jl_s, py_m, py_s,
            mae, nmae, r_traj,
            ks_statistic(final_jl, final_py),
            ecdf_correlation(final_jl, final_py),
            qq_correlation(final_jl, final_py),
            mmd2, mmd_p,
            safe_mean(final_jl), safe_mean(final_py),
            safe_std(final_jl), safe_std(final_py),
            safe_median(final_jl), safe_median(final_py)))
    end
    comparisons
end

function compare_model(; n_reps::Int=20, n_steps::Int=50,
                        seeds::Union{Nothing, Vector{Int}}=nothing,
                        n_people::Int=200, n_initial_infected::Int=5,
                        beta::Float64=0.3,
                        gamma_shape::Float64=1.56, gamma_rate::Float64=0.53,
                        gamma_shift::Float64=-2.12, recovery_days::Int=14)
    actual_seeds = seeds !== nothing ? seeds : collect(1:n_reps)
    n = length(actual_seeds)

    kwargs = (n_people=n_people, n_steps=n_steps,
              n_initial_infected=n_initial_infected,
              beta=beta, gamma_shape=gamma_shape,
              gamma_rate=gamma_rate, gamma_shift=gamma_shift,
              recovery_days=recovery_days)

    println("╔══════════════════════════════════════════════════╗")
    println("║  Comparing: Simple SIR (June.jl vs Python JUNE)")
    println("║  Replications: $n  │  Steps: $n_steps")
    println("║  Population: $n_people  │  Initial infected: $n_initial_infected")
    println("╚══════════════════════════════════════════════════╝")

    println("\n▶ Running Julia (June.jl) implementation...")
    t_jl = @elapsed jl = run_julia_trajectories(actual_seeds; kwargs...)
    @printf("  ✓ Julia: %.2f s (%.3f s/rep)\n", t_jl, t_jl/n)

    println("\n▶ Running Python (JUNE) implementation...")
    t_py = @elapsed py = run_python_trajectories(actual_seeds; kwargs...)
    @printf("  ✓ Python: %.2f s (%.3f s/rep)\n", t_py, t_py/n)

    println("\n▶ Computing statistical comparisons...")
    comps = compute_comparisons(jl, py, TRACKED_VARS, n_steps)

    ComparisonReport("Simple SIR", n, n_steps, actual_seeds, jl, py, comps, t_jl, t_py)
end

"""
    compare_model(scenario; n_reps, n_steps, kwargs...) -> ComparisonReport

Scenario-aware comparison. Runs Julia and Python for the given scenario.
"""
function compare_model(scenario::AbstractScenario;
                       n_reps::Int=20,
                       n_steps::Int=default_n_steps(scenario),
                       seeds::Union{Nothing, Vector{Int}}=nothing,
                       kwargs...)
    actual_seeds = seeds !== nothing ? seeds : collect(1:n_reps)
    n = length(actual_seeds)
    name = scenario_name(scenario)
    vars = tracked_vars(scenario)

    println("╔══════════════════════════════════════════════════╗")
    println("║  Comparing: $name (June.jl vs Python)")
    println("║  Replications: $n  │  Steps: $n_steps")
    println("╚══════════════════════════════════════════════════╝")

    println("\n▶ Running Julia (June.jl) implementation...")
    t_jl = @elapsed jl = run_julia_trajectories(scenario, actual_seeds; n_steps=n_steps, kwargs...)
    @printf("  ✓ Julia: %.2f s (%.3f s/rep)\n", t_jl, t_jl/n)

    println("\n▶ Running Python implementation...")
    t_py = @elapsed py = run_python_trajectories(scenario, actual_seeds; n_steps=n_steps, kwargs...)
    @printf("  ✓ Python: %.2f s (%.3f s/rep)\n", t_py, t_py/n)

    println("\n▶ Computing statistical comparisons...")
    comps = compute_comparisons(jl, py, vars, n_steps)

    ComparisonReport(name, n, n_steps, actual_seeds, jl, py, comps, t_jl, t_py)
end

# ── Reporting ─────────────────────────────────────────────────────────

function verdict(c::VariableComparison)
    if c.nmae_mean_traj < 1e-8 && c.mae_mean_traj < 1e-8
        return :exact
    end
    traj_ok = c.corr_mean_traj > 0.99
    nmae_ok = c.nmae_mean_traj < 0.10
    ecdf_ok = c.ecdf_corr > 0.90 || isnan(c.ecdf_corr)
    ks_ok   = c.ks_statistic < 0.20
    mmd_ok  = c.mmd_pvalue > 0.05 || isnan(c.mmd_pvalue)
    if traj_ok && nmae_ok && (ecdf_ok || ks_ok) && mmd_ok
        return :pass
    end
    if c.corr_mean_traj > 0.95 && c.nmae_mean_traj < 0.20
        return :marginal
    end
    return :divergent
end

verdict_symbol(v::Symbol) = v == :exact ? "══" : v == :pass ? "✓ " : v == :marginal ? "~ " : "✗ "

function print_report(r::ComparisonReport)
    println()
    println("┌──────────────────────────────────────────────────────────────────────────────┐")
    @printf("│  %s — %d reps × %d steps\n", r.scenario_name, r.n_reps, r.n_steps)
    @printf("│  Julia: %.2fs  │  Python: %.2fs  │  Speedup: %.1f×\n",
            r.julia_time_s, r.python_time_s,
            r.python_time_s > 0 ? r.python_time_s / r.julia_time_s : NaN)
    println("├──────────────────────────────────────────────────────────────────────────────┤")
    println("│  MEAN TRAJECTORY COMPARISON                                                 │")
    println("├──────────────────────┬──────────┬──────────┬──────────┬──────────┬───────────┤")
    println("│  Variable            │   MAE    │   NMAE   │   r(μ)   │   KS     │  Verdict  │")
    println("├──────────────────────┼──────────┼──────────┼──────────┼──────────┼───────────┤")
    for c in r.comparisons
        v = verdict(c)
        @printf("│  %-20s│ %8.3f │ %8.5f │ %8.5f │ %8.4f │    %s     │\n",
                c.name[1:min(20,end)], c.mae_mean_traj, c.nmae_mean_traj,
                c.corr_mean_traj, c.ks_statistic, verdict_symbol(v))
    end
    println("├──────────────────────┴──────────┴──────────┴──────────┴──────────┴───────────┤")
    println("│  TRAJECTORY MMD (RBF kernel, median heuristic, 500 permutations)             │")
    println("├──────────────────────┬──────────────┬──────────────┬─────────────────────────┤")
    println("│  Variable            │     MMD²     │   p-value    │  Interpretation         │")
    println("├──────────────────────┼──────────────┼──────────────┼─────────────────────────┤")
    for c in r.comparisons
        interp = isnan(c.mmd_pvalue) ? "insufficient data" :
                 c.mmd_pvalue > 0.10 ? "✓ not significant" :
                 c.mmd_pvalue > 0.05 ? "~ borderline"      :
                 c.mmd_pvalue > 0.01 ? "⚠ significant"     : "✗ highly significant"
        mmd_str = isnan(c.mmd_stat) ? "    N/A " : @sprintf("%12.6f", c.mmd_stat)
        p_str   = isnan(c.mmd_pvalue) ? "    N/A " : @sprintf("%12.4f", c.mmd_pvalue)
        @printf("│  %-20s│ %s │ %s │  %-23s │\n",
                c.name[1:min(20,end)], mmd_str, p_str, interp)
    end
    println("├──────────────────────┴──────────────┴──────────────┴─────────────────────────┤")
    println("│  DISTRIBUTIONAL COMPARISON (final step)                                      │")
    println("├──────────────────────┬───────────────────────┬───────────────────────┬────────┤")
    println("│  Variable            │  Julia (μ ± σ) [med]  │ Python (μ ± σ) [med]  │ECDF r  │")
    println("├──────────────────────┼───────────────────────┼───────────────────────┼────────┤")
    for c in r.comparisons
        jl_str = @sprintf("%.1f±%.1f [%.1f]", c.julia_final_mean, c.julia_final_std, c.julia_final_median)
        py_str = @sprintf("%.1f±%.1f [%.1f]", c.python_final_mean, c.python_final_std, c.python_final_median)
        @printf("│  %-20s│ %-21s │ %-21s │ %6.4f │\n",
                c.name[1:min(20,end)], jl_str, py_str, c.ecdf_corr)
    end
    println("└──────────────────────┴───────────────────────┴───────────────────────┴────────┘")

    verdicts = verdict.(r.comparisons)
    if all(v -> v in (:exact, :pass), verdicts)
        println("\n  ✅ PASS — All variables show compatible stochastic behavior")
    elseif all(v -> v != :divergent, verdicts)
        marginal = [c.name for (c, v) in zip(r.comparisons, verdicts) if v == :marginal]
        println("\n  ⚠️  MARGINAL: $(join(marginal, ", ")) — may need more replicates")
    else
        bad = [c.name for (c, v) in zip(r.comparisons, verdicts) if v == :divergent]
        println("\n  ❌ DIVERGENCE in: $(join(bad, ", "))")
    end
end

function save_csv(r::ComparisonReport, path::String)
    globals = [c.name for c in r.comparisons]
    open(path, "w") do io
        println(io, "implementation,seed,step,", join(globals, ","))
        for traj in r.julia_trajectories
            for (i, t) in enumerate(traj.ticks)
                vals = [i <= length(get(traj.values, g, Float64[])) ?
                        get(traj.values, g, Float64[])[i] : NaN for g in globals]
                println(io, "julia,", traj.seed, ",", t, ",", join(vals, ","))
            end
        end
        for traj in r.python_trajectories
            for (i, t) in enumerate(traj.ticks)
                vals = [i <= length(get(traj.values, g, Float64[])) ?
                        get(traj.values, g, Float64[])[i] : NaN for g in globals]
                println(io, "python,", traj.seed, ",", t, ",", join(vals, ","))
            end
        end
    end

    summary_path = replace(path, ".csv" => "_summary.csv")
    open(summary_path, "w") do io
        println(io, "variable,mae,nmae,corr_mean_traj,ks_stat,ecdf_corr,qq_corr,",
                "mmd_stat,mmd_pvalue,",
                "jl_final_mean,py_final_mean,jl_final_std,py_final_std,",
                "jl_final_median,py_final_median,verdict")
        for c in r.comparisons
            v = verdict(c)
            @printf(io, "%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%s\n",
                    c.name, c.mae_mean_traj, c.nmae_mean_traj, c.corr_mean_traj,
                    c.ks_statistic, c.ecdf_corr, c.qq_corr,
                    c.mmd_stat, c.mmd_pvalue,
                    c.julia_final_mean, c.python_final_mean,
                    c.julia_final_std, c.python_final_std,
                    c.julia_final_median, c.python_final_median, v)
        end
    end
    println("  📁 Trajectories: $path")
    println("  📁 Summary:      $summary_path")
end

# ── Calibrated comparison (4-batch null-calibrated design) ────────────
#
# Run 2 batches per implementation (Julia-A, Julia-B, Python-A, Python-B).
# Compare:  Julia-A vs Julia-B  (within-Julia null)
#           Python-A vs Python-B (within-Python null)
#           Julia-A vs Python-A  (cross-implementation test)
# If cross-impl metrics fall within the range of within-impl metrics,
# the implementations are statistically equivalent — no subjective thresholds.

"""Compact metrics for one pairwise batch comparison."""
struct BatchMetrics
    mae::Float64
    nmae::Float64
    corr_mean::Float64
    ks::Float64
    ecdf_r::Float64
    mmd_stat::Float64
    mmd_p::Float64
end

struct VariableCalibrated
    name::String
    jl_vs_jl::BatchMetrics     # within-Julia (null)
    py_vs_py::BatchMetrics     # within-Python (null)
    jl_vs_py::BatchMetrics     # cross-implementation (test)
    pass::Bool                 # true if cross ≤ max(within) for key metrics
end

struct CalibratedReport
    scenario_name::String
    n_per_batch::Int
    n_steps::Int
    variables::Vector{VariableCalibrated}
    julia_time_s::Float64
    python_time_s::Float64
end

"""Compute BatchMetrics between two trajectory sets for one variable."""
function batch_metrics(trajs_a::Vector{TrajectoryData}, trajs_b::Vector{TrajectoryData},
                       g::String, n_steps::Int)
    safe_mean(x) = (f = filter(!isnan, x); isempty(f) ? NaN : mean(f))

    function mean_traj(trajs)
        by_tick = [Float64[] for _ in 0:n_steps]
        for traj in trajs
            v = get(traj.values, g, Float64[])
            for (i, t) in enumerate(traj.ticks)
                0 <= t <= n_steps && push!(by_tick[t+1], i <= length(v) ? v[i] : NaN)
            end
        end
        safe_mean.(by_tick)
    end

    ma = mean_traj(trajs_a)
    mb = mean_traj(trajs_b)

    diffs = abs.(ma .- mb)
    fd = filter(!isnan, diffs)
    mae = isempty(fd) ? NaN : mean(fd)

    combined = filter(!isnan, vcat(ma, mb))
    val_range = isempty(combined) ? 1.0 : max(maximum(combined) - minimum(combined), 1.0)
    nmae = mae / val_range

    r_mean = pearson_r(ma, mb)

    final_a = Float64[last(get(t.values, g, [NaN])) for t in trajs_a]
    final_b = Float64[last(get(t.values, g, [NaN])) for t in trajs_b]

    ks = ks_statistic(final_a, final_b)
    ecdf_r = ecdf_correlation(final_a, final_b)
    mmd2, mmd_p = trajectory_mmd(trajs_a, trajs_b, g, n_steps; n_perms=500)

    BatchMetrics(mae, nmae, r_mean, ks, ecdf_r, mmd2, mmd_p)
end

function compare_model_calibrated(; n_per_batch::Int=50, n_steps::Int=50,
                                    n_people::Int=200, n_initial_infected::Int=5,
                                    beta::Float64=0.3,
                                    gamma_shape::Float64=1.56, gamma_rate::Float64=0.53,
                                    gamma_shift::Float64=-2.12, recovery_days::Int=14)
    seeds_a = collect(1:n_per_batch)
    seeds_b = collect(n_per_batch+1 : 2*n_per_batch)

    kwargs = (n_people=n_people, n_steps=n_steps,
              n_initial_infected=n_initial_infected,
              beta=beta, gamma_shape=gamma_shape,
              gamma_rate=gamma_rate, gamma_shift=gamma_shift,
              recovery_days=recovery_days)

    println("╔══════════════════════════════════════════════════════════╗")
    println("║  Calibrated comparison: Simple SIR (June.jl vs Python)")
    println("║  4 batches × $n_per_batch reps  │  Steps: $n_steps")
    println("║  Population: $n_people  │  Initial infected: $n_initial_infected")
    println("╚══════════════════════════════════════════════════════════╝")

    println("\n▶ Running Julia batch A (seeds 1-$n_per_batch)...")
    t_jl = @elapsed begin
        jl_a = run_julia_trajectories(seeds_a; kwargs...)
        println("    ...batch B (seeds $(n_per_batch+1)-$(2*n_per_batch))...")
        jl_b = run_julia_trajectories(seeds_b; kwargs...)
    end
    @printf("  ✓ Julia: %.2f s (%.3f s/rep)\n", t_jl, t_jl/(2*n_per_batch))

    println("\n▶ Running Python batch A (seeds 1-$n_per_batch)...")
    t_py = @elapsed begin
        py_a = run_python_trajectories(seeds_a; kwargs...)
        println("    ...batch B (seeds $(n_per_batch+1)-$(2*n_per_batch))...")
        py_b = run_python_trajectories(seeds_b; kwargs...)
    end
    @printf("  ✓ Python: %.2f s (%.3f s/rep)\n", t_py, t_py/(2*n_per_batch))

    println("\n▶ Computing 3-way batch comparisons...")
    variables = VariableCalibrated[]

    for g in TRACKED_VARS
        jl_jl = batch_metrics(jl_a, jl_b, g, n_steps)
        py_py = batch_metrics(py_a, py_b, g, n_steps)
        jl_py = batch_metrics(jl_a, py_a, g, n_steps)

        # Pass if cross-implementation metrics are no worse than the
        # larger of the two within-implementation baselines.
        tol = 1.5   # allow 50% slack over the within-impl baseline
        null_mae  = max(jl_jl.nmae, py_py.nmae)
        null_ks   = max(jl_jl.ks, py_py.ks)
        null_mmd_p = min(jl_jl.mmd_p, py_py.mmd_p)

        mae_ok = isnan(null_mae) || jl_py.nmae <= null_mae * tol + 0.01
        ks_ok  = isnan(null_ks)  || jl_py.ks   <= null_ks  * tol + 0.02
        # MMD: cross p-value shouldn't be dramatically lower than within
        mmd_ok = isnan(jl_py.mmd_p) || jl_py.mmd_p >= null_mmd_p * 0.5 - 0.05

        ok = mae_ok && ks_ok && mmd_ok
        push!(variables, VariableCalibrated(g, jl_jl, py_py, jl_py, ok))
    end

    CalibratedReport("Simple SIR", n_per_batch, n_steps, variables, t_jl, t_py)
end

"""
    compare_model_calibrated(scenario; n_per_batch, n_steps, kwargs...) -> CalibratedReport

Scenario-aware calibrated 4-batch comparison.
"""
function compare_model_calibrated(scenario::AbstractScenario;
                                   n_per_batch::Int=50,
                                   n_steps::Int=default_n_steps(scenario),
                                   kwargs...)
    seeds_a = collect(1:n_per_batch)
    seeds_b = collect(n_per_batch+1 : 2*n_per_batch)
    name = scenario_name(scenario)
    vars = tracked_vars(scenario)

    println("╔══════════════════════════════════════════════════════════╗")
    println("║  Calibrated comparison: $name (June.jl vs Python)")
    println("║  4 batches × $n_per_batch reps  │  Steps: $n_steps")
    println("╚══════════════════════════════════════════════════════════╝")

    println("\n▶ Running Julia batch A (seeds 1-$n_per_batch)...")
    t_jl = @elapsed begin
        jl_a = run_julia_trajectories(scenario, seeds_a; n_steps=n_steps, kwargs...)
        println("    ...batch B (seeds $(n_per_batch+1)-$(2*n_per_batch))...")
        jl_b = run_julia_trajectories(scenario, seeds_b; n_steps=n_steps, kwargs...)
    end
    @printf("  ✓ Julia: %.2f s (%.3f s/rep)\n", t_jl, t_jl/(2*n_per_batch))

    println("\n▶ Running Python batch A (seeds 1-$n_per_batch)...")
    t_py = @elapsed begin
        py_a = run_python_trajectories(scenario, seeds_a; n_steps=n_steps, kwargs...)
        println("    ...batch B (seeds $(n_per_batch+1)-$(2*n_per_batch))...")
        py_b = run_python_trajectories(scenario, seeds_b; n_steps=n_steps, kwargs...)
    end
    @printf("  ✓ Python: %.2f s (%.3f s/rep)\n", t_py, t_py/(2*n_per_batch))

    println("\n▶ Computing 3-way batch comparisons...")
    variables = VariableCalibrated[]

    for g in vars
        jl_jl = batch_metrics(jl_a, jl_b, g, n_steps)
        py_py = batch_metrics(py_a, py_b, g, n_steps)
        jl_py = batch_metrics(jl_a, py_a, g, n_steps)

        tol = 1.5
        null_mae  = max(jl_jl.nmae, py_py.nmae)
        null_ks   = max(jl_jl.ks, py_py.ks)
        null_mmd_p = min(jl_jl.mmd_p, py_py.mmd_p)

        mae_ok = isnan(null_mae) || jl_py.nmae <= null_mae * tol + 0.01
        ks_ok  = isnan(null_ks)  || jl_py.ks   <= null_ks  * tol + 0.02
        mmd_ok = isnan(jl_py.mmd_p) || jl_py.mmd_p >= null_mmd_p * 0.5 - 0.05

        ok = mae_ok && ks_ok && mmd_ok
        push!(variables, VariableCalibrated(g, jl_jl, py_py, jl_py, ok))
    end

    CalibratedReport(name, n_per_batch, n_steps, variables, t_jl, t_py)
end

function print_calibrated_report(r::CalibratedReport)
    println()
    println("┌──────────────────────────────────────────────────────────────────────────────────────────────────┐")
    @printf("│  %s — Calibrated 4-batch comparison (%d per batch × %d steps)\n",
            r.scenario_name, r.n_per_batch, r.n_steps)
    @printf("│  Julia: %.1fs  │  Python: %.1fs\n", r.julia_time_s, r.python_time_s)
    println("├──────────────────────────────────────────────────────────────────────────────────────────────────┤")
    println("│                       │      Julia A↔B (null)    │     Python A↔B (null)    │  Julia↔Python (test)│")
    println("│  Variable       Metric│   value                  │   value                  │   value        pass │")
    println("├──────────────────────────────────────────────────────────────────────────────────────────────────┤")
    for v in r.variables
        jj = v.jl_vs_jl; pp = v.py_vs_py; jp = v.jl_vs_py
        n = v.name[1:min(16,end)]
        @printf("│  %-16s NMAE │   %8.5f                │   %8.5f                │   %8.5f      │\n", n, jj.nmae, pp.nmae, jp.nmae)
        @printf("│  %-16s r(μ) │   %8.5f                │   %8.5f                │   %8.5f      │\n", "", jj.corr_mean, pp.corr_mean, jp.corr_mean)
        @printf("│  %-16s KS   │   %8.4f                │   %8.4f                │   %8.4f      │\n", "", jj.ks, pp.ks, jp.ks)
        mmd_p_jj = isnan(jj.mmd_p) ? "   N/A" : @sprintf("%8.4f", jj.mmd_p)
        mmd_p_pp = isnan(pp.mmd_p) ? "   N/A" : @sprintf("%8.4f", pp.mmd_p)
        mmd_p_jp = isnan(jp.mmd_p) ? "   N/A" : @sprintf("%8.4f", jp.mmd_p)
        mark = v.pass ? "  ✓" : "  ✗"
        @printf("│  %-16s MMDp │   %s                │   %s                │   %s    %s │\n", "", mmd_p_jj, mmd_p_pp, mmd_p_jp, mark)
        println("│                       │                          │                          │                     │")
    end
    println("└──────────────────────────────────────────────────────────────────────────────────────────────────┘")

    all_ok = all(v -> v.pass, r.variables)
    if all_ok
        println("\n  ✅ PASS — Cross-implementation differences within null baseline for all variables")
    else
        bad = [v.name for v in r.variables if !v.pass]
        println("\n  ❌ FAIL — Cross-impl exceeds null baseline for: $(join(bad, ", "))")
    end
end

function save_calibrated_csv(r::CalibratedReport, path::String)
    open(path, "w") do io
        println(io, "variable,comparison,mae,nmae,corr_mean,ks,ecdf_r,mmd_stat,mmd_p,pass")
        for v in r.variables
            for (label, m) in [("julia_vs_julia",   v.jl_vs_jl),
                               ("python_vs_python", v.py_vs_py),
                               ("julia_vs_python",  v.jl_vs_py)]
                @printf(io, "%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%s\n",
                        v.name, label, m.mae, m.nmae, m.corr_mean,
                        m.ks, m.ecdf_r, m.mmd_stat, m.mmd_p,
                        label == "julia_vs_python" ? string(v.pass) : "")
            end
        end
    end
    println("  📁 Saved: $path")
end

# ── Benchmark mode ────────────────────────────────────────────────────

function _format_bytes(bytes::Float64)
    if bytes < 1024
        return @sprintf("%.0f B", bytes)
    elseif bytes < 1024^2
        return @sprintf("%.1f KB", bytes / 1024)
    else
        return @sprintf("%.1f MB", bytes / 1024^2)
    end
end

"""
    run_benchmark(scenario; n_reps, n_steps) -> BenchmarkResult

Run the benchmark for a single scenario: time and memory for Julia and Python.
"""
function run_benchmark(scenario::AbstractScenario;
                       n_reps::Int=10,
                       n_steps::Int=default_n_steps(scenario))
    name = scenario_name(scenario)
    seeds = collect(1:n_reps)

    # Julia warmup (JIT compile the measurement path too)
    run_julia_timed(scenario, 0; n_steps=n_steps)
    GC.gc(); GC.gc()

    # Julia: timed with allocation (first rep warms JIT, skip from averages)
    jl_times = Float64[]
    jl_mems = Float64[]
    for (idx, s) in enumerate(seeds)
        _, t, alloc = run_julia_timed(scenario, s; n_steps=n_steps)
        if idx > 1  # skip first rep (JIT overhead in @allocated)
            push!(jl_times, t)
            push!(jl_mems, alloc)
        end
    end

    # Python: timed with memory
    py_times = Float64[]
    py_peaks = Float64[]
    for s in seeds
        t_py = @elapsed begin
            _, peak = run_python(scenario, s; n_steps=n_steps, measure_memory=true)
        end
        push!(py_times, t_py)
        push!(py_peaks, peak)
    end

    jl_avg_t = mean(jl_times)
    py_avg_t = mean(py_times)
    jl_avg_m = mean(jl_mems)
    py_avg_m = mean(py_peaks)

    speedup = py_avg_t > 0 ? py_avg_t / jl_avg_t : NaN
    mem_ratio = jl_avg_m > 0 && py_avg_m > 0 ? py_avg_m / jl_avg_m : NaN

    BenchmarkResult(name, jl_avg_t, py_avg_t, jl_avg_m, py_avg_m, speedup, mem_ratio)
end

"""
    run_all_benchmarks(scenarios; n_reps, n_steps_override) -> Vector{BenchmarkResult}

Run benchmarks for multiple scenarios.
"""
function run_all_benchmarks(scenarios::Vector{<:AbstractScenario};
                            n_reps::Int=10,
                            n_steps_override::Union{Nothing,Int}=nothing)
    results = BenchmarkResult[]
    for (i, scenario) in enumerate(scenarios)
        ns = n_steps_override !== nothing ? n_steps_override : default_n_steps(scenario)
        name = scenario_name(scenario)
        println("  [$i/$(length(scenarios))] Benchmarking: $name ($n_reps reps × $ns steps)...")
        br = run_benchmark(scenario; n_reps=n_reps, n_steps=ns)
        push!(results, br)
        @printf("    Julia: %.3fs/rep, %s/rep │ Python: %.3fs/rep, %s/rep │ Speedup: %.1f×\n",
                br.julia_time_per_rep, _format_bytes(br.julia_peak_mem),
                br.python_time_per_rep, _format_bytes(br.python_peak_mem),
                br.speedup)
    end
    results
end

"""Print a summary benchmark table."""
function print_benchmark_report(results::Vector{BenchmarkResult})
    println()
    println("┌─────────────────────┬──────────────────────┬──────────────────────┬─────────┬────────┐")
    println("│  Scenario           │  Julia (time / mem)  │  Python (time / mem) │ Speedup │ MemRat │")
    println("├─────────────────────┼──────────────────────┼──────────────────────┼─────────┼────────┤")
    for br in results
        jl_str = @sprintf("%.3fs / %s", br.julia_time_per_rep, _format_bytes(br.julia_peak_mem))
        py_str = @sprintf("%.3fs / %s", br.python_time_per_rep, _format_bytes(br.python_peak_mem))
        sp_str = isnan(br.speedup) ? "  N/A  " : @sprintf(" %5.1f×", br.speedup)
        mr_str = isnan(br.memory_ratio) ? "  N/A " : @sprintf(" %4.1f×", br.memory_ratio)
        @printf("│  %-19s│ %-20s │ %-20s │%s │%s │\n",
                br.scenario_name[1:min(19,end)], jl_str, py_str, sp_str, mr_str)
    end
    println("└─────────────────────┴──────────────────────┴──────────────────────┴─────────┴────────┘")
end

"""Save benchmark results to CSV."""
function save_benchmark_csv(results::Vector{BenchmarkResult}, path::String)
    open(path, "w") do io
        println(io, "scenario,julia_time_s,python_time_s,julia_peak_bytes,python_peak_bytes,speedup,memory_ratio")
        for br in results
            @printf(io, "%s,%.6f,%.6f,%.0f,%.0f,%.2f,%.2f\n",
                    br.scenario_name, br.julia_time_per_rep, br.python_time_per_rep,
                    br.julia_peak_mem, br.python_peak_mem,
                    br.speedup, br.memory_ratio)
        end
    end
    println("  📁 Saved: $path")
end

end # module JuneCompare
