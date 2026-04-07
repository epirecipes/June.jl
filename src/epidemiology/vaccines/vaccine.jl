# ============================================================================
# Vaccine / Dose / VaccineTrajectory
#
# Included inside `module June`; no sub-module wrapper.
# Assumes Person, Immunity helpers are available.
# ============================================================================

# ---------------------------------------------------------------------------
# Dose
# ---------------------------------------------------------------------------
mutable struct Dose
    sterilisation_efficacy::Dict{Int, Float64}    # infection_id → efficacy
    symptomatic_efficacy::Dict{Int, Float64}
    days_administered_to_effective::Float64
    days_effective_to_waning::Float64
    days_waning::Float64
    waning_factor::Float64
    date_administered::Any                         # Date or nothing
    prior_sterilisation::Dict{Int, Float64}
    prior_symptomatic::Dict{Int, Float64}
end

_elapsed_days(date::Date, reference::Date) = Float64(Dates.value(date - reference))
_elapsed_days(date::DateTime, reference::DateTime) =
    Float64(Dates.value(date - reference)) / (24.0 * 3_600_000)
_elapsed_days(date::DateTime, reference::Date) =
    Float64(Dates.value(Date(date) - reference))
_elapsed_days(date::Date, reference::DateTime) =
    Float64(Dates.value(date - Date(reference)))

function Dose(;
    sterilisation_efficacy::Dict{Int, Float64} = Dict{Int, Float64}(),
    symptomatic_efficacy::Dict{Int, Float64}   = Dict{Int, Float64}(),
    days_administered_to_effective::Float64     = 14.0,
    days_effective_to_waning::Float64           = 180.0,
    days_waning::Float64                        = 90.0,
    waning_factor::Float64                      = 0.5,
)
    return Dose(
        sterilisation_efficacy, symptomatic_efficacy,
        days_administered_to_effective, days_effective_to_waning,
        days_waning, waning_factor,
        nothing,
        Dict{Int, Float64}(),
        Dict{Int, Float64}(),
    )
end

"""
    get_efficacy(dose::Dose, date, infection_id::Int, protection_type::Symbol)

Compute the current efficacy of a dose on `date` for the given
`protection_type` (`:sterilisation` or `:symptomatic`).

Phases:
1. Before effective: linear ramp from prior → full efficacy
2. Effective plateau: full efficacy
3. Waning: linear decline to `waning_factor × efficacy`
4. After waning: stays at `waning_factor × efficacy`
"""
function get_efficacy(dose::Dose, date, infection_id::Int, protection_type::Symbol)
    dose.date_administered === nothing && return 0.0

    days_since = _elapsed_days(date, dose.date_administered)
    days_since < 0.0 && return 0.0

    if protection_type == :sterilisation
        full_eff = get(dose.sterilisation_efficacy, infection_id, 0.0)
        prior    = get(dose.prior_sterilisation, infection_id, 0.0)
    else
        full_eff = get(dose.symptomatic_efficacy, infection_id, 0.0)
        prior    = get(dose.prior_symptomatic, infection_id, 0.0)
    end

    # Phase 1: ramp up
    if days_since < dose.days_administered_to_effective
        frac = days_since / dose.days_administered_to_effective
        return prior + (full_eff - prior) * frac
    end

    days_effective = days_since - dose.days_administered_to_effective

    # Phase 2: plateau
    if days_effective < dose.days_effective_to_waning
        return full_eff
    end

    days_waning = days_effective - dose.days_effective_to_waning

    # Phase 3: waning
    if days_waning < dose.days_waning
        waned_eff = full_eff * dose.waning_factor
        frac = days_waning / dose.days_waning
        return full_eff + (waned_eff - full_eff) * frac
    end

    # Phase 4: post-waning
    return full_eff * dose.waning_factor
end

# ---------------------------------------------------------------------------
# Vaccine
# ---------------------------------------------------------------------------
struct Vaccine
    name::String
    doses::Vector{Dict}          # per-dose config dictionaries
    waning_factor::Float64
end

"""
    vaccine_from_config(config::Dict, name::String)

Create a `Vaccine` from a YAML-like config dictionary.
"""
function vaccine_from_config(config::Dict, name::String)
    doses = get(config, "doses", Dict[])
    waning = Float64(get(config, "waning_factor", 0.5))
    return Vaccine(name, doses, waning)
end

# ---------------------------------------------------------------------------
# VaccineTrajectory — tracks a person's vaccine history
# ---------------------------------------------------------------------------
mutable struct VaccineTrajectory
    vaccine::Vaccine
    doses::Vector{Dose}
    current_dose::Int
end

VaccineTrajectory(vaccine::Vaccine) = VaccineTrajectory(vaccine, Dose[], 0)

"""
    administer_dose!(vt::VaccineTrajectory, date; dose_number::Int=0)

Add a new dose to the trajectory.  If `dose_number` is 0, the next dose in
sequence is used.
"""
function administer_dose!(vt::VaccineTrajectory, date; dose_number::Int=0)
    dn = dose_number == 0 ? vt.current_dose + 1 : dose_number
    dn > length(vt.vaccine.doses) && return nothing

    dose_config = vt.vaccine.doses[dn]

    ster = Dict{Int, Float64}()
    symp = Dict{Int, Float64}()

    if haskey(dose_config, "sterilisation_efficacy")
        for (k, v) in dose_config["sterilisation_efficacy"]
            iid = isa(k, Integer) ? Int(k) : parse(Int, string(k))
            ster[iid] = Float64(v)
        end
    end
    if haskey(dose_config, "symptomatic_efficacy")
        for (k, v) in dose_config["symptomatic_efficacy"]
            iid = isa(k, Integer) ? Int(k) : parse(Int, string(k))
            symp[iid] = Float64(v)
        end
    end

    days_to_eff = Float64(get(dose_config, "days_administered_to_effective", 14.0))
    days_eff_wan = Float64(get(dose_config, "days_effective_to_waning", 180.0))
    days_wan = Float64(get(dose_config, "days_waning", 90.0))
    wf = Float64(get(dose_config, "waning_factor", vt.vaccine.waning_factor))

    dose = Dose(;
        sterilisation_efficacy = ster,
        symptomatic_efficacy   = symp,
        days_administered_to_effective = days_to_eff,
        days_effective_to_waning = days_eff_wan,
        days_waning = days_wan,
        waning_factor = wf,
    )
    dose.date_administered = date

    # Carry forward prior efficacies from the previous dose
    if !isempty(vt.doses)
        prev = vt.doses[end]
        for (iid, _) in ster
            dose.prior_sterilisation[iid] = get_efficacy(prev, date, iid, :sterilisation)
        end
        for (iid, _) in symp
            dose.prior_symptomatic[iid] = get_efficacy(prev, date, iid, :symptomatic)
        end
    end

    push!(vt.doses, dose)
    vt.current_dose = dn
    return nothing
end

"""
    update_vaccine_effect!(vt::VaccineTrajectory, person::Person, date, record)

Update the person's immunity based on current vaccine efficacy.
"""
function update_vaccine_effect!(vt::VaccineTrajectory, person::Person, date, record)
    isempty(vt.doses) && return nothing
    dose = vt.doses[end]

    if person.immunity === nothing
        person.immunity = Immunity()
    end

    for (iid, _) in dose.sterilisation_efficacy
        eff = get_efficacy(dose, date, iid, :sterilisation)
        susc = 1.0 - eff
        person.immunity.susceptibility_dict[iid] = max(susc, 0.0)
    end

    for (iid, _) in dose.symptomatic_efficacy
        eff = get_efficacy(dose, date, iid, :symptomatic)
        mult = 1.0 - eff
        person.immunity.effective_multiplier_dict[iid] = max(mult, 0.0)
    end

    return nothing
end
