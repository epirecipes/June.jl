# ============================================================================
# VaccinationCampaign — schedule and administer vaccines
#
# Included inside `module June`; no sub-module wrapper.
# Assumes Vaccine, VaccineTrajectory, Dose, Person are available.
# ============================================================================

mutable struct VaccinationCampaign
    vaccine::Vaccine
    start_time::Any              # Date or nothing
    end_time::Any                # Date or nothing
    group_by::String             # e.g. "age", "sector"
    group_type::String           # e.g. "80+", "healthcare"
    group_coverage::Float64      # target fraction (0–1)
    dose_numbers::Vector{Int}
    days_to_next_dose::Vector{Float64}
end

"""
    should_be_vaccinated(vc::VaccinationCampaign, person::Person)::Bool

Check whether `person` matches the campaign's target group.
"""
function should_be_vaccinated(vc::VaccinationCampaign, person::Person)::Bool
    if vc.group_by == "age"
        return _person_in_age_group(person.age, vc.group_type)
    elseif vc.group_by == "sector"
        return person.sector !== nothing && person.sector == vc.group_type
    end
    return false
end

function _person_in_age_group(age::Int, group_type::String)
    if endswith(group_type, "+")
        low = parse(Int, group_type[1:end-1])
        return age >= low
    elseif occursin("-", group_type)
        parts = split(group_type, "-")
        low = parse(Int, parts[1])
        high = parse(Int, parts[2])
        return low <= age <= high
    else
        return age == parse(Int, group_type)
    end
end

"""
    vaccinate!(vc::VaccinationCampaign, person::Person, date, record)

Administer the appropriate dose to `person`, creating a `VaccineTrajectory`
if the person has not yet been vaccinated with this vaccine.
"""
function vaccinate!(vc::VaccinationCampaign, person::Person, date, record)
    if person.vaccine_trajectory !== nothing &&
       person.vaccine_type !== nothing &&
       person.vaccine_type != vc.vaccine.name
        @warn "Skipping incompatible vaccine campaign for person $(person.id): $(person.vaccine_type) vs $(vc.vaccine.name)"
        return nothing
    end

    # Create trajectory if needed
    if person.vaccine_trajectory === nothing
        person.vaccine_trajectory = VaccineTrajectory(vc.vaccine)
        person.vaccine_type = vc.vaccine.name
    end

    vt = person.vaccine_trajectory
    next_dose = vt.current_dose + 1

    # Check if this dose is in the campaign's schedule
    next_dose in vc.dose_numbers || return nothing

    if next_dose > 1 && !isempty(vt.doses)
        gap_idx = next_dose - 1
        if length(vc.days_to_next_dose) >= gap_idx
            min_gap = vc.days_to_next_dose[gap_idx]
            days_since_last_dose = _elapsed_days(date, vt.doses[end].date_administered)
            days_since_last_dose < min_gap && return nothing
        end
    end

    administer_dose!(vt, date; dose_number=next_dose)
    person.vaccinated = next_dose

    if record !== nothing
        accumulate_vaccine!(
            record;
            person_id=person.id,
            vaccine_name=vc.vaccine.name,
            dose_number=next_dose,
            date=string(date),
        )
    end

    return nothing
end

# ---------------------------------------------------------------------------
# VaccinationCampaigns — container
# ---------------------------------------------------------------------------

mutable struct VaccinationCampaigns
    campaigns::Vector{VaccinationCampaign}
end

VaccinationCampaigns() = VaccinationCampaigns(VaccinationCampaign[])

"""
    apply!(campaigns::VaccinationCampaigns, person::Person, date, record)

Check each campaign and vaccinate `person` if eligible.
"""
function apply!(campaigns::VaccinationCampaigns, person::Person, date, record)
    for vc in campaigns.campaigns
        # Check timing
        if vc.start_time !== nothing && date < vc.start_time
            continue
        end
        if vc.end_time !== nothing && date > vc.end_time
            continue
        end

        if should_be_vaccinated(vc, person) && rand() < vc.group_coverage
            vaccinate!(vc, person, date, record)
        end
    end
    return nothing
end
