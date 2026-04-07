# ============================================================================
# HealthIndexGenerator — age/sex-dependent outcome probabilities
#
# Included inside `module June`; no sub-module wrapper.
# Assumes Person, CSV, DataFrames, YAML are available.
# ============================================================================

# ---------------------------------------------------------------------------
# The cumulative-probability table has one row per age (0–99) and columns for
# each outcome level: asymptomatic → mild → severe → hospitalised →
# intensive_care → dead_home → dead_hospital → dead_icu.
# ---------------------------------------------------------------------------

const _N_OUTCOME_LEVELS = 8

struct HealthIndexGenerator
    female_health_index::Matrix{Float64}   # 100 × _N_OUTCOME_LEVELS
    male_health_index::Matrix{Float64}     # 100 × _N_OUTCOME_LEVELS
    comorbidity_multipliers::Dict{String, Float64}
end

"""
    HealthIndexGenerator(; female_data, male_data, comorbidity_multipliers)

Build from pre-loaded matrices (rows = ages 0–99, cols = outcome levels).
"""
function HealthIndexGenerator(;
    female_data::Matrix{Float64} = zeros(100, _N_OUTCOME_LEVELS),
    male_data::Matrix{Float64}   = zeros(100, _N_OUTCOME_LEVELS),
    comorbidity_multipliers::Dict{String, Float64} = Dict{String, Float64}(),
)
    return HealthIndexGenerator(female_data, male_data, comorbidity_multipliers)
end

"""
    health_index_from_file(config_path::String)

Load a `HealthIndexGenerator` from a YAML config that points to CSV data files.
Expected YAML keys: `female_file`, `male_file`, and optionally `comorbidity_multipliers`.
"""
function health_index_from_file(config_path::String)
    config = YAML.load_file(config_path)
    base_dir = dirname(config_path)

    female_file = joinpath(base_dir, config["female_file"])
    male_file   = joinpath(base_dir, config["male_file"])

    female_df = CSV.read(female_file, DataFrame; header=false)
    male_df   = CSV.read(male_file,   DataFrame; header=false)

    female_data = Matrix{Float64}(female_df)
    male_data   = Matrix{Float64}(male_df)

    cm = Dict{String, Float64}()
    if haskey(config, "comorbidity_multipliers")
        for (k, v) in config["comorbidity_multipliers"]
            cm[string(k)] = Float64(v)
        end
    end

    return HealthIndexGenerator(;
        female_data = female_data,
        male_data   = male_data,
        comorbidity_multipliers = cm,
    )
end

"""
    get_health_index(hig::HealthIndexGenerator, person::Person, infection_id::Int)::Vector{Float64}

Return a cumulative probability vector for the person's age, sex, and
comorbidity status.  The returned vector has `_N_OUTCOME_LEVELS` entries.
"""
function get_health_index(hig::HealthIndexGenerator, person::Person, infection_id::Int)::Vector{Float64}
    age_idx = clamp(person.age, 0, 99) + 1   # 1-based row

    base = if person.sex == 'f'
        hig.female_health_index[age_idx, :]
    else
        hig.male_health_index[age_idx, :]
    end

    hi = copy(vec(base))

    # Apply comorbidity multiplier if applicable
    if person.comorbidity !== nothing && haskey(hig.comorbidity_multipliers, person.comorbidity)
        mult = hig.comorbidity_multipliers[person.comorbidity]
        for i in eachindex(hi)
            hi[i] = min(hi[i] * mult, 1.0)
        end
        # Re-enforce monotonicity (cumulative must be non-decreasing)
        for i in 2:length(hi)
            hi[i] = max(hi[i], hi[i-1])
        end
    end

    # Apply immunity effective multiplier
    if person.immunity !== nothing
        eff = get_effective_multiplier(person.immunity, infection_id)
        for i in eachindex(hi)
            hi[i] = min(hi[i] * eff, 1.0)
        end
        for i in 2:length(hi)
            hi[i] = max(hi[i], hi[i-1])
        end
    end

    return hi
end
