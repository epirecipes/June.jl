# ============================================================================
# InteractiveGroup — pre-processed snapshot of a Group optimised for
# infection-transmission calculations
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

"""
    InteractiveGroup

Pre-processed snapshot of a `Group` optimised for infection-transmission
calculations.  Separates susceptibles and infectors by subgroup and
infection variant so that the inner loop of the interaction engine can
work with plain dictionaries and vectors instead of querying person
objects every time-step.
"""
mutable struct InteractiveGroup
    group::Group
    spec::String

    # subgroup_idx => person_id => infection_id => susceptibility
    susceptibles_per_subgroup::Dict{Int, Dict{Int, Dict{Int, Float64}}}

    # infection_id => subgroup_idx => (ids, trans_probs)
    infectors_per_infection_per_subgroup::Dict{Int, Dict{Int, NamedTuple{(:ids, :trans_probs), Tuple{Vector{Int}, Vector{Float64}}}}}

    subgroup_sizes::Dict{Int, Int}
    must_timestep::Bool
    size::Int
end

# ── Constructor ──────────────────────────────────────────────────────────

"""
    InteractiveGroup(group; people_from_abroad=nothing)

Build an `InteractiveGroup` from a `Group`.

`people_from_abroad` — optional `Dict{Int, Dict}` keyed by subgroup type,
with per-person dicts containing `"susc"`, `"immunity_inf_ids"`,
`"immunity_suscs"`, `"inf_id"`, `"inf_prob"` fields.
"""
function InteractiveGroup(group::Group; people_from_abroad = nothing)
    if people_from_abroad === nothing
        people_from_abroad = Dict{Int, Dict}()
    end

    susceptibles = Dict{Int, Dict{Int, Dict{Int, Float64}}}()
    infectors    = Dict{Int, Dict{Int, NamedTuple{(:ids, :trans_probs), Tuple{Vector{Int}, Vector{Float64}}}}}()
    sg_sizes     = Dict{Int, Int}()
    total_size   = 0

    for (sg_idx, sg) in enumerate(group.subgroups)
        sg_size = length(sg.people)

        # People from abroad for this subgroup
        abroad_data = get(people_from_abroad, sg.subgroup_type, nothing)
        abroad_ids  = abroad_data === nothing ? Int[] : collect(keys(abroad_data))
        sg_size += length(abroad_ids)

        sg_size == 0 && continue

        sg_sizes[sg_idx] = sg_size
        total_size += sg_size

        # ── Local susceptibles ───────────────────────────────────────
        for person in sg.people
            if !is_infected(person) && !person.dead
                susc_dict = Dict{Int, Float64}()
                if person.immunity !== nothing &&
                   hasproperty(person.immunity, :susceptibility_dict)
                    for (vid, sval) in person.immunity.susceptibility_dict
                        susc_dict[vid] = sval
                    end
                else
                    susc_dict[0] = 1.0   # default: fully susceptible to variant 0
                end
                if !haskey(susceptibles, sg_idx)
                    susceptibles[sg_idx] = Dict{Int, Dict{Int, Float64}}()
                end
                susceptibles[sg_idx][person.id] = susc_dict
            end
        end

        # ── Abroad susceptibles ──────────────────────────────────────
        if abroad_data !== nothing
            for aid in abroad_ids
                pdata = abroad_data[aid]
                if get(pdata, "susc", false)
                    dd = Dict{Int, Float64}()
                    inf_ids = get(pdata, "immunity_inf_ids", Int[])
                    suscs   = get(pdata, "immunity_suscs", Float64[])
                    for (k, v) in zip(inf_ids, suscs)
                        dd[k] = v
                    end
                    if !haskey(susceptibles, sg_idx)
                        susceptibles[sg_idx] = Dict{Int, Dict{Int, Float64}}()
                    end
                    susceptibles[sg_idx][aid] = dd
                end
            end
        end

        # ── Local infectors ──────────────────────────────────────────
        for person in sg.people
            if person.infection !== nothing
                inf_id = _infection_id(person.infection)
                if !haskey(infectors, inf_id)
                    infectors[inf_id] = Dict{Int, NamedTuple{(:ids, :trans_probs), Tuple{Vector{Int}, Vector{Float64}}}}()
                end
                if !haskey(infectors[inf_id], sg_idx)
                    infectors[inf_id][sg_idx] = (ids = Int[], trans_probs = Float64[])
                end
                push!(infectors[inf_id][sg_idx].ids, person.id)
                push!(infectors[inf_id][sg_idx].trans_probs,
                      _transmission_probability(person.infection))
            end
        end

        # ── Abroad infectors ─────────────────────────────────────────
        if abroad_data !== nothing
            for aid in abroad_ids
                pdata = abroad_data[aid]
                iid = get(pdata, "inf_id", 0)
                if iid != 0
                    if !haskey(infectors, iid)
                        infectors[iid] = Dict{Int, NamedTuple{(:ids, :trans_probs), Tuple{Vector{Int}, Vector{Float64}}}}()
                    end
                    if !haskey(infectors[iid], sg_idx)
                        infectors[iid][sg_idx] = (ids = Int[], trans_probs = Float64[])
                    end
                    push!(infectors[iid][sg_idx].ids, aid)
                    push!(infectors[iid][sg_idx].trans_probs,
                          get(pdata, "inf_prob", 0.0))
                end
            end
        end
    end

    _must = !isempty(susceptibles) && !isempty(infectors)

    return InteractiveGroup(
        group,
        group.spec,
        susceptibles,
        infectors,
        sg_sizes,
        _must,
        total_size,
    )
end

# ── Internal helpers (safe accessors for infection fields) ───────────────

function _infection_id(infection)
    if hasproperty(infection, :infection_id)
        iid = infection.infection_id
        return isa(iid, Function) ? iid() : iid
    end
    return 0
end

function _transmission_probability(infection)
    if hasproperty(infection, :transmission)
        t = infection.transmission
        if hasproperty(t, :probability)
            return Float64(t.probability)
        end
    end
    return 0.0
end

# ── Queries ──────────────────────────────────────────────────────────────

"""True when at least one subgroup has susceptible people."""
has_susceptible(ig::InteractiveGroup) = !isempty(ig.susceptibles_per_subgroup)

"""True when at least one infection-variant has infectors."""
has_infectors(ig::InteractiveGroup) = !isempty(ig.infectors_per_infection_per_subgroup)

# ── Beta processing ──────────────────────────────────────────────────────

"""
    get_processed_beta(ig, beta; beta_reductions=Dict(), regional_compliance=1.0)

Compute the effective transmission rate for this group, applying policy-
driven reductions and regional compliance.

    β_eff = β × (1 + regional_compliance × tier_reduction × (β_reduction − 1))

* `beta` — base transmission rate for the group spec
* `beta_reductions` — Dict{String, Float64} of spec → reduction factor
* `regional_compliance` — 0–1 adherence scalar
"""
function get_processed_beta(ig::InteractiveGroup, beta::Float64;
                            beta_reductions::Dict{String, Float64} = Dict{String, Float64}(),
                            regional_compliance::Float64 = 1.0)
    beta_reduction = get(beta_reductions, ig.spec, 1.0)

    # Determine lockdown tier from the group's region (if available)
    lockdown_tier = 1
    try
        if ig.group.area !== nothing
            sa = ig.group.area
            if hasproperty(sa, :super_area)
                sa = sa.super_area
            end
            if hasproperty(sa, :region) && sa.region !== nothing
                reg = sa.region
                if hasproperty(reg, :lockdown_tier)
                    lt = reg.lockdown_tier
                    if lt !== nothing
                        lockdown_tier = Int(lt)
                    end
                end
                if hasproperty(reg, :regional_compliance)
                    regional_compliance = Float64(reg.regional_compliance)
                end
            end
        end
    catch
        # Fall through with defaults
    end

    tier_reduction = lockdown_tier == 4 ? 0.5 : 1.0

    return beta * (1.0 + regional_compliance * tier_reduction * (beta_reduction - 1.0))
end

# ── Contact-matrix processing ────────────────────────────────────────────

"""
    get_raw_contact_matrix(contact_matrix, alpha_physical,
                           proportion_physical, characteristic_time)

Process a contact matrix for transmission:

1. Boost physical contacts:
   `C′ = C .* (1 + (α_phys − 1) .* P_phys)`
2. Normalise by characteristic time:
   `C′′ = C′ .* (24 / t_char)`

Arguments are plain arrays/scalars — this is a **static** helper.
"""
function get_raw_contact_matrix(contact_matrix::Matrix{Float64},
                                alpha_physical::Float64,
                                proportion_physical::Matrix{Float64},
                                characteristic_time::Float64)
    processed = contact_matrix .* (1.0 .+ (alpha_physical - 1.0) .* proportion_physical)
    processed .*= 24.0 / characteristic_time
    return processed
end

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, ig::InteractiveGroup)
    ns = sum(length(v) for (_, v) in ig.susceptibles_per_subgroup; init = 0)
    ni = sum(
        sum(length(sg.ids) for (_, sg) in vdict; init = 0)
        for (_, vdict) in ig.infectors_per_infection_per_subgroup;
        init = 0
    )
    print(io, "InteractiveGroup(spec=\"$(ig.spec)\", susceptibles=$ns, infectors=$ni, must=$(ig.must_timestep))")
end
