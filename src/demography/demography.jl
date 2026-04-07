# ---------------------------------------------------------------------------
# Demography — population generation from census data
# ---------------------------------------------------------------------------

struct AgeSexGenerator
    n_residents::Int
    age_counts::Vector{Int}       # count per age (index = age+1 for 0-based age)
    sex_bins::Vector{Int}         # age boundaries for sex ratio bins
    female_fractions::Vector{Float64}  # fraction female in each sex bin
    ethnicity_groups::Union{Nothing, Vector{String}}
    ethnicity_structure::Union{Nothing, Vector{Vector{Int}}}  # per age_bin, integer weights
    ethnicity_age_bins::Union{Nothing, Vector{Int}}
    max_age::Int
end

"""
    parse_age_bin(s::String) -> Tuple{Int,Int}

Parse an age-bin string like `"25-34"` into `(25, 34)`.
"""
function parse_age_bin(s::String)::Tuple{Int,Int}
    parts = split(s, "-")
    return (parse(Int, parts[1]), parse(Int, parts[2]))
end

"""
    generate_age(gen::AgeSexGenerator) -> Int

Sample an age from the population's single-year age distribution.
"""
function generate_age(gen::AgeSexGenerator)::Int
    total = sum(gen.age_counts)
    total == 0 && return 0
    weights = Weights(Float64.(gen.age_counts))
    return sample(0:(length(gen.age_counts)-1), weights)
end

"""
    generate_sex(gen::AgeSexGenerator, age::Int) -> Char

Sample sex ('m' or 'f') based on age-specific female fractions.
"""
function generate_sex(gen::AgeSexGenerator, age::Int)::Char
    bin_idx = 1
    for (i, boundary) in enumerate(gen.sex_bins)
        if age >= boundary
            bin_idx = i
        else
            break
        end
    end
    bin_idx = min(bin_idx, length(gen.female_fractions))
    return rand() < gen.female_fractions[bin_idx] ? 'f' : 'm'
end

"""
    generate_ethnicity(gen::AgeSexGenerator, age::Int) -> Union{Nothing,String}

Sample ethnicity from age-stratified ethnicity weights.
Returns `nothing` if no ethnicity data is available.
"""
function generate_ethnicity(gen::AgeSexGenerator, age::Int)::Union{Nothing,String}
    isnothing(gen.ethnicity_groups) && return nothing
    isnothing(gen.ethnicity_structure) && return nothing
    isnothing(gen.ethnicity_age_bins) && return nothing
    isempty(gen.ethnicity_groups) && return nothing

    bin_idx = 1
    for (i, boundary) in enumerate(gen.ethnicity_age_bins)
        if age >= boundary
            bin_idx = i
        else
            break
        end
    end
    bin_idx = min(bin_idx, length(gen.ethnicity_structure))
    weights_vec = gen.ethnicity_structure[bin_idx]
    total = sum(weights_vec)
    total == 0 && return gen.ethnicity_groups[1]
    w = Weights(Float64.(weights_vec))
    return gen.ethnicity_groups[sample(1:length(gen.ethnicity_groups), w)]
end

# ---------------------------------------------------------------------------
# ComorbidityGenerator
# ---------------------------------------------------------------------------

struct ComorbidityGenerator
    male_probabilities::Matrix{Float64}    # comorbidity × age_bins
    female_probabilities::Matrix{Float64}
    age_bins::Vector{Int}
    comorbidities::Vector{String}
end

"""
    comorbidity_generator_from_file(; male_path, female_path) -> ComorbidityGenerator

Load male/female comorbidity CSV files. Each CSV has columns: comorbidity, then
one column per age bin whose header encodes the bin boundaries.
"""
function comorbidity_generator_from_file(; male_path::String, female_path::String)
    male_df   = CSV.read(male_path,   DataFrame)
    female_df = CSV.read(female_path, DataFrame)

    comorbidities = string.(male_df[:, 1])
    age_bin_strs  = string.(names(male_df)[2:end])
    age_bins      = [parse_age_bin(s)[1] for s in age_bin_strs]

    n_comorb   = length(comorbidities)
    n_age_bins = length(age_bins)

    male_probs   = zeros(n_comorb, n_age_bins)
    female_probs = zeros(n_comorb, n_age_bins)
    for j in 1:n_age_bins
        male_probs[:, j]   = Float64.(male_df[:, j+1])
        female_probs[:, j] = Float64.(female_df[:, j+1])
    end

    return ComorbidityGenerator(male_probs, female_probs, age_bins, comorbidities)
end

"""
    get_comorbidity(gen::ComorbidityGenerator, person::Person) -> Union{Nothing,String}

Sample a comorbidity for `person` based on their age and sex.
"""
function get_comorbidity(gen::ComorbidityGenerator, person::Person)::Union{Nothing,String}
    isempty(gen.comorbidities) && return nothing

    bin_idx = 1
    for (i, boundary) in enumerate(gen.age_bins)
        if person.age >= boundary
            bin_idx = i
        else
            break
        end
    end
    bin_idx = min(bin_idx, length(gen.age_bins))

    probs = person.sex == 'f' ? gen.female_probabilities : gen.male_probabilities

    for c in 1:length(gen.comorbidities)
        if rand() < probs[c, bin_idx]
            return gen.comorbidities[c]
        end
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Demography
# ---------------------------------------------------------------------------

mutable struct Demography
    area_names::Vector{String}
    age_sex_generators::Dict{String, AgeSexGenerator}
    comorbidity_generator::Union{Nothing, ComorbidityGenerator}
end

"""
    demography_for_areas(area_names; data_path=nothing) -> Demography

Build a `Demography` object from CSV census files:
- `age_structure_single_year.csv`
- `female_ratios_per_age_bin.csv`
- `ethnicity_structure.csv` (optional)
- comorbidity CSVs (optional)
"""
function demography_for_areas(area_names::AbstractVector{<:AbstractString};
                              data_path::Union{Nothing,String}=nothing)
    if isnothing(data_path)
        data_path = default_data_path("demographics")
    end

    # --- age structure --------------------------------------------------
    age_path = joinpath(data_path, "age_structure_single_year.csv")
    age_df   = CSV.read(age_path, DataFrame)

    # --- female ratios --------------------------------------------------
    sex_path = joinpath(data_path, "female_ratios_per_age_bin.csv")
    sex_df   = CSV.read(sex_path, DataFrame)
    sex_bin_strs     = string.(names(sex_df)[2:end])
    sex_bins         = [parse_age_bin(s)[1] for s in sex_bin_strs]

    # --- ethnicity (optional) -------------------------------------------
    eth_path = joinpath(data_path, "ethnicity_structure.csv")
    has_ethnicity = isfile(eth_path)
    eth_df = has_ethnicity ? CSV.read(eth_path, DataFrame) : nothing

    ethnicity_groups   = nothing
    ethnicity_age_bins = nothing
    if has_ethnicity && !isnothing(eth_df) && ncol(eth_df) > 2
        ethnicity_groups   = string.(names(eth_df)[3:end])
        ethnicity_age_bins = Int[]
    end

    # --- comorbidity (optional) -----------------------------------------
    male_comorb_path   = joinpath(data_path, "comorbidity_male.csv")
    female_comorb_path = joinpath(data_path, "comorbidity_female.csv")
    comorb_gen = nothing
    if isfile(male_comorb_path) && isfile(female_comorb_path)
        comorb_gen = comorbidity_generator_from_file(
            male_path=male_comorb_path, female_path=female_comorb_path)
    end

    # --- build per-area generators --------------------------------------
    generators = Dict{String, AgeSexGenerator}()
    age_col_names = string.(names(age_df))
    area_col = age_col_names[1]

    for area_name in area_names
        row_idx = findfirst(r -> string(r) == area_name, age_df[:, 1])
        if isnothing(row_idx)
            @warn "Area $area_name not found in age structure data"
            continue
        end

        age_counts = Int[age_df[row_idx, c] for c in 2:ncol(age_df)]
        max_age    = length(age_counts) - 1

        # female fractions for this area
        sex_row_idx = findfirst(r -> string(r) == area_name, sex_df[:, 1])
        female_fractions = if !isnothing(sex_row_idx)
            Float64[sex_df[sex_row_idx, c] for c in 2:ncol(sex_df)]
        else
            fill(0.5, length(sex_bins))
        end

        # ethnicity weights for this area
        eth_structure = nothing
        eth_age_bins_local = nothing
        if has_ethnicity && !isnothing(eth_df) && !isnothing(ethnicity_groups)
            eth_rows = findall(r -> string(r) == area_name, eth_df[:, 1])
            if !isempty(eth_rows)
                eth_structure = Vector{Int}[]
                eth_age_bins_local = Int[]
                for ri in eth_rows
                    push!(eth_age_bins_local, 0)  # placeholder — parsed from col 2 if present
                    row_weights = Int[eth_df[ri, c] for c in 3:ncol(eth_df)]
                    push!(eth_structure, row_weights)
                end
            end
        end

        n_residents = sum(age_counts)
        gen = AgeSexGenerator(
            n_residents, age_counts, sex_bins, female_fractions,
            ethnicity_groups, eth_structure, eth_age_bins_local, max_age)
        generators[area_name] = gen
    end

    return Demography(collect(String, area_names), generators, comorb_gen)
end

"""
    demography_for_geography(geography) -> Demography

Extract area names from a `Geography` and delegate to `demography_for_areas`.
"""
function demography_for_geography(geography)
    area_names = [a.name for a in geography.areas.members]
    return demography_for_areas(area_names)
end

"""
    populate!(dem::Demography, area_name::String; ethnicity=true, comorbidity=true) -> Population

Generate a `Population` of `Person` objects for the given area using census data.
"""
function populate!(dem::Demography, area_name::String;
                   ethnicity::Bool=true, comorbidity::Bool=true)::Population
    pop = Population()
    haskey(dem.age_sex_generators, area_name) || return pop

    gen = dem.age_sex_generators[area_name]
    for _ in 1:gen.n_residents
        age = generate_age(gen)
        sex = generate_sex(gen, age)

        eth = ethnicity ? generate_ethnicity(gen, age) : nothing

        person = Person(; sex=sex, age=age, ethnicity=eth)

        if comorbidity && !isnothing(dem.comorbidity_generator)
            person.comorbidity = get_comorbidity(dem.comorbidity_generator, person)
        end

        push!(pop, person)
    end
    return pop
end
