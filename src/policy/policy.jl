# ============================================================================
# Policy — simulation policies (individual, interaction, leisure, medical, regional)
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

abstract type AbstractPolicy end

"""
    is_active(p::AbstractPolicy, date::DateTime)

True when `date` falls within the policy's [start_time, end_time) window.
"""
function is_active(p::AbstractPolicy, date::DateTime)
    start_ok = p.start_time === nothing || date >= p.start_time
    end_ok   = p.end_time === nothing   || date < p.end_time
    return start_ok && end_ok
end

# ---------------------------------------------------------------------------
# Base Policy
# ---------------------------------------------------------------------------

mutable struct Policy <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
end

Policy() = Policy(nothing, nothing)

# ---------------------------------------------------------------------------
# Individual Policies
# ---------------------------------------------------------------------------

struct StayHome <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
    compliance::Float64
end

struct Quarantine <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
    n_days::Int
    compliance::Float64
    household_compliance::Float64
end

struct SevereSymptomsStayHome <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
end

struct Shielding <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
    min_age::Int
    compliance::Float64
end

struct SkipActivity <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
    activities_to_skip::Vector{Symbol}
end

struct SchoolQuarantine <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
    n_days::Int
    compliance::Float64
end

# ---------------------------------------------------------------------------
# Interaction Policies
# ---------------------------------------------------------------------------

struct SocialDistancing <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
    beta_factors::Dict{String, Float64}
end

struct MaskWearing <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
    mask_probability::Float64
    compliance::Float64
    beta_factor::Float64
end

# ---------------------------------------------------------------------------
# Leisure Policies
# ---------------------------------------------------------------------------

struct CloseLeisureVenue <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
    venues_to_close::Vector{String}
end

struct ChangeLeisureProbability <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
    activity_reductions::Dict{String, Float64}
end

# ---------------------------------------------------------------------------
# Medical Care
# ---------------------------------------------------------------------------

struct Hospitalisation <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
end

# ---------------------------------------------------------------------------
# Regional
# ---------------------------------------------------------------------------

struct RegionalCompliance <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
    regional_compliance::Dict{String, Float64}
end

struct TieredLockdown <: AbstractPolicy
    start_time::Union{Nothing, DateTime}
    end_time::Union{Nothing, DateTime}
    tiers::Dict{String, Int}
end

# ---------------------------------------------------------------------------
# Policy Collections
# ---------------------------------------------------------------------------

mutable struct Policies
    individual_policies::Vector{AbstractPolicy}
    interaction_policies::Vector{AbstractPolicy}
    leisure_policies::Vector{AbstractPolicy}
    medical_care_policies::Vector{AbstractPolicy}
    regional_compliance::Vector{AbstractPolicy}
end

Policies() = Policies(
    AbstractPolicy[], AbstractPolicy[], AbstractPolicy[],
    AbstractPolicy[], AbstractPolicy[]
)

"""
    policies_from_file(config_path::String)

Load policies from a YAML config file.
"""
function policies_from_file(config_path::String)
    cfg = YAML.load_file(config_path)
    pol_cfg = get(cfg, "policies", cfg)
    policies = Policies()

    for p_cfg in get(pol_cfg, "individual", [])
        pol = _parse_individual_policy(p_cfg)
        pol !== nothing && push!(policies.individual_policies, pol)
    end
    for p_cfg in get(pol_cfg, "interaction", [])
        pol = _parse_interaction_policy(p_cfg)
        pol !== nothing && push!(policies.interaction_policies, pol)
    end
    for p_cfg in get(pol_cfg, "leisure", [])
        pol = _parse_leisure_policy(p_cfg)
        pol !== nothing && push!(policies.leisure_policies, pol)
    end
    for p_cfg in get(pol_cfg, "medical_care", [])
        pol = _parse_medical_policy(p_cfg)
        pol !== nothing && push!(policies.medical_care_policies, pol)
    end
    for p_cfg in get(pol_cfg, "regional_compliance", [])
        pol = _parse_regional_policy(p_cfg)
        pol !== nothing && push!(policies.regional_compliance, pol)
    end
    return policies
end

# ---------------------------------------------------------------------------
# YAML parsers for individual policy types
# ---------------------------------------------------------------------------

function _parse_datetime(val)
    val === nothing && return nothing
    return DateTime(string(val), dateformat"yyyy-mm-dd")
end

function _parse_individual_policy(cfg)
    ptype = get(cfg, "type", "")
    st = _parse_datetime(get(cfg, "start_time", nothing))
    et = _parse_datetime(get(cfg, "end_time", nothing))
    if ptype == "stay_home"
        return StayHome(st, et, Float64(get(cfg, "compliance", 1.0)))
    elseif ptype == "quarantine"
        return Quarantine(st, et,
            Int(get(cfg, "n_days", 14)),
            Float64(get(cfg, "compliance", 1.0)),
            Float64(get(cfg, "household_compliance", 0.5)))
    elseif ptype == "severe_symptoms_stay_home"
        return SevereSymptomsStayHome(st, et)
    elseif ptype == "shielding"
        return Shielding(st, et, Int(get(cfg, "min_age", 70)), Float64(get(cfg, "compliance", 1.0)))
    elseif ptype == "skip_activity"
        acts = Symbol.(get(cfg, "activities_to_skip", String[]))
        return SkipActivity(st, et, acts)
    elseif ptype == "school_quarantine"
        return SchoolQuarantine(st, et, Int(get(cfg, "n_days", 14)), Float64(get(cfg, "compliance", 1.0)))
    end
    return nothing
end

function _parse_interaction_policy(cfg)
    ptype = get(cfg, "type", "")
    st = _parse_datetime(get(cfg, "start_time", nothing))
    et = _parse_datetime(get(cfg, "end_time", nothing))
    if ptype == "social_distancing"
        factors = Dict{String, Float64}(
            String(k) => Float64(v) for (k, v) in get(cfg, "beta_factors", Dict())
        )
        return SocialDistancing(st, et, factors)
    elseif ptype == "mask_wearing"
        return MaskWearing(st, et,
            Float64(get(cfg, "mask_probability", 0.5)),
            Float64(get(cfg, "compliance", 1.0)),
            Float64(get(cfg, "beta_factor", 0.5)))
    end
    return nothing
end

function _parse_leisure_policy(cfg)
    ptype = get(cfg, "type", "")
    st = _parse_datetime(get(cfg, "start_time", nothing))
    et = _parse_datetime(get(cfg, "end_time", nothing))
    if ptype == "close_leisure_venue"
        venues = String.(get(cfg, "venues_to_close", String[]))
        return CloseLeisureVenue(st, et, venues)
    elseif ptype == "change_leisure_probability"
        reds = Dict{String, Float64}(
            String(k) => Float64(v) for (k, v) in get(cfg, "activity_reductions", Dict())
        )
        return ChangeLeisureProbability(st, et, reds)
    end
    return nothing
end

function _parse_medical_policy(cfg)
    st = _parse_datetime(get(cfg, "start_time", nothing))
    et = _parse_datetime(get(cfg, "end_time", nothing))
    return Hospitalisation(st, et)
end

function _parse_regional_policy(cfg)
    ptype = get(cfg, "type", "")
    st = _parse_datetime(get(cfg, "start_time", nothing))
    et = _parse_datetime(get(cfg, "end_time", nothing))
    if ptype == "regional_compliance"
        rc = Dict{String, Float64}(
            String(k) => Float64(v) for (k, v) in get(cfg, "regional_compliance", Dict())
        )
        return RegionalCompliance(st, et, rc)
    elseif ptype == "tiered_lockdown"
        tiers = Dict{String, Int}(
            String(k) => Int(v) for (k, v) in get(cfg, "tiers", Dict())
        )
        return TieredLockdown(st, et, tiers)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Policy application methods
# ---------------------------------------------------------------------------

"""
    apply_individual!(policies::Policies, person::Person, activities_list, date)

Apply all active individual policies to a person, potentially modifying which
activities the person can participate in.  Returns the (possibly filtered)
activity list.
"""
function apply_individual!(policies::Policies, person::Person,
                           activities_list::Vector{String}, date::DateTime)
    result = copy(activities_list)
    for pol in policies.individual_policies
        !is_active(pol, date) && continue

        if pol isa StayHome
            if rand() < pol.compliance
                filter!(a -> a == "residence" || a == "medical_facility", result)
            end
        elseif pol isa Quarantine
            if person.lockdown_status == "quarantine" && rand() < pol.compliance
                filter!(a -> a == "residence" || a == "medical_facility", result)
            end
        elseif pol isa SchoolQuarantine
            primary = person.subgroups.primary_activity
            if person.lockdown_status == "quarantine" &&
               primary !== nothing &&
               hasproperty(primary, :group) &&
               primary.group !== nothing &&
               primary.group.spec == "school" &&
               rand() < pol.compliance
                filter!(a -> a == "residence" || a == "medical_facility", result)
            end
        elseif pol isa SevereSymptomsStayHome
            sym = symptoms(person)
            if sym !== nothing &&
               symptom_value(sym.tag) >= symptom_value(severe)
                filter!(a -> a == "residence" || a == "medical_facility", result)
            end
        elseif pol isa Shielding
            if person.age >= pol.min_age && rand() < pol.compliance
                filter!(a -> a == "residence" || a == "medical_facility", result)
            end
        elseif pol isa SkipActivity
            filter!(a -> Symbol(a) ∉ pol.activities_to_skip, result)
        end
    end
    return result
end

"""
    apply_interaction!(policies::Policies, date::DateTime, interaction::Interaction)

Apply active interaction policies (social distancing, mask wearing) by
adjusting `interaction.beta_reductions`.
"""
function apply_interaction!(policies::Policies, date::DateTime,
                            interaction::Interaction)
    empty!(interaction.beta_reductions)
    for pol in policies.interaction_policies
        !is_active(pol, date) && continue

        if pol isa SocialDistancing
            for (spec, factor) in pol.beta_factors
                current = get(interaction.beta_reductions, spec, 1.0)
                interaction.beta_reductions[spec] = current * factor
            end
        elseif pol isa MaskWearing
            overall_factor = 1.0 - pol.mask_probability * pol.compliance * (1.0 - pol.beta_factor)
            for spec in keys(interaction.betas)
                current = get(interaction.beta_reductions, spec, 1.0)
                interaction.beta_reductions[spec] = current * overall_factor
            end
        end
    end
end

"""
    apply_leisure!(policies::Policies, date::DateTime, leisure)

Apply active leisure policies (venue closures, probability changes).
"""
function apply_leisure!(policies::Policies, date::DateTime, leisure)
    for pol in policies.leisure_policies
        !is_active(pol, date) && continue

        if pol isa CloseLeisureVenue && leisure !== nothing
            try
                for venue_type in pol.venues_to_close
                    if hasproperty(leisure, Symbol(venue_type * "_open"))
                        setproperty!(leisure, Symbol(venue_type * "_open"), false)
                    end
                end
            catch
            end
        elseif pol isa ChangeLeisureProbability && leisure !== nothing
            try
                for (act, reduction) in pol.activity_reductions
                    if hasproperty(leisure, Symbol(act * "_probability"))
                        current = getproperty(leisure, Symbol(act * "_probability"))
                        setproperty!(leisure, Symbol(act * "_probability"), current * reduction)
                    end
                end
            catch
            end
        end
    end
end

"""
    apply_medical_care!(policies::Policies, person::Person, date::DateTime,
                        world, record)

Apply medical care policies (hospitalisation) to a person.
"""
function apply_medical_care!(policies::Policies, person::Person,
                             date::DateTime, world, record)
    for pol in policies.medical_care_policies
        !is_active(pol, date) && continue

        if pol isa Hospitalisation
            # Hospitalisation logic delegated to epidemiology module
        end
    end
end

"""
    apply_regional_compliance!(policies::Policies, date::DateTime, regions)

Apply regional compliance and tiered lockdown policies.
"""
function apply_regional_compliance!(policies::Policies, date::DateTime, regions)
    regions === nothing && return nothing
    for pol in policies.regional_compliance
        !is_active(pol, date) && continue

        if pol isa RegionalCompliance
            for (region_name, compliance) in pol.regional_compliance
                for r in regions
                    if r.name == region_name
                        r.regional_compliance = compliance
                    end
                end
            end
        elseif pol isa TieredLockdown
            for (region_name, tier) in pol.tiers
                for r in regions
                    if r.name == region_name
                        r.lockdown_tier = tier
                    end
                end
            end
        end
    end
end

function Base.show(io::IO, p::Policies)
    n = sum(length, [p.individual_policies, p.interaction_policies,
                     p.leisure_policies, p.medical_care_policies,
                     p.regional_compliance])
    print(io, "Policies(total=$n)")
end
