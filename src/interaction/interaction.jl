# ============================================================================
# Interaction — infection transmission logic across groups
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

mutable struct Interaction
    alpha_physical::Float64
    betas::Dict{String, Float64}
    contact_matrices::Dict{String, Matrix{Float64}}
    beta_reductions::Dict{String, Float64}
end

"""
    interaction_from_file(config_path::String)

Construct an `Interaction` from a YAML config file.
"""
function interaction_from_file(config_path::String)
    cfg = YAML.load_file(config_path)
    alpha_physical = Float64(get(cfg, "alpha_physical", 2.0))
    betas = Dict{String, Float64}(
        String(k) => Float64(v) for (k, v) in get(cfg, "betas", Dict())
    )
    input_cms = get(cfg, "contact_matrices", Dict())
    groups = collect(keys(betas))
    contact_matrices = get_raw_contact_matrices(;
        input_contact_matrices=input_cms, groups=groups, alpha_physical=alpha_physical
    )
    return Interaction(alpha_physical, betas, contact_matrices, Dict{String, Float64}())
end

"""
    get_raw_contact_matrices(; input_contact_matrices, groups, alpha_physical)

Process raw contact matrices from config.  For each group spec, apply the
physical-contact correction and characteristic-time normalisation.
"""
function get_raw_contact_matrices(; input_contact_matrices, groups, alpha_physical)
    result = Dict{String, Matrix{Float64}}()
    for spec in groups
        if haskey(input_contact_matrices, spec)
            cm_config = input_contact_matrices[spec]
            contacts = Float64.(cm_config["contacts"])
            proportion_physical = Float64.(
                get(cm_config, "proportion_physical", zeros(size(contacts)))
            )
            characteristic_time = Float64(get(cm_config, "characteristic_time", 24.0))
            processed = contacts .* (1.0 .+ (alpha_physical - 1.0) .* proportion_physical) .*
                        (24.0 / characteristic_time)
            result[spec] = processed
        else
            result[spec] = ones(1, 1)
        end
    end
    return result
end

"""
    time_step_for_group!(interaction::Interaction, group::Group;
                         people_from_abroad=nothing, delta_time=1.0, record=nothing)

Run a single infection time-step for `group`.  Returns
`(infected_ids, infection_ids, group_size)`.
"""
function time_step_for_group!(interaction::Interaction, group::Group;
                              people_from_abroad=nothing, delta_time::Float64=1.0,
                              record=nothing)
    ig = InteractiveGroup(group; people_from_abroad=people_from_abroad)
    group_size = n_people(group)

    if group_size == 0
        return Int[], Int[], 0
    end

    spec = ig.group.spec
    beta = get(interaction.betas, spec, 0.0)
    contact_matrix = get(interaction.contact_matrices, spec, ones(1, 1))

    processed_beta = get_processed_beta(ig, beta; beta_reductions=interaction.beta_reductions)

    infected_ids = Int[]
    infection_ids = Int[]

    # Collect infectors: person → transmission probability and variant id
    infectors = Dict{Int, NamedTuple{(:prob, :infection_id), Tuple{Float64, Int}}}()
    for sg in group.subgroups
        for p in sg.people
            if is_infected(p) && p.infection !== nothing
                trans = try
                    p.infection.transmission.probability
                catch
                    0.0
                end
                if trans > 0.0
                    infectors[p.id] = (prob=trans, infection_id=p.infection.infection_id)
                end
            end
        end
    end

    if isempty(infectors)
        return Int[], Int[], group_size
    end

    # Compute total infector pressure per subgroup
    n_sg = length(group.subgroups)
    infector_pressure = zeros(n_sg)
    for (sg_idx, sg) in enumerate(group.subgroups)
        sg_size = max(length(sg), 1)
        for p in sg.people
            if haskey(infectors, p.id)
                infector_pressure[sg_idx] += infectors[p.id].prob / sg_size
            end
        end
    end

    # Attempt infection on each susceptible
    for (sg_idx, sg) in enumerate(group.subgroups)
        for p in sg.people
            if is_infected(p) || p.dead
                continue
            end
            total_exposure = 0.0
            best_infector_id = 0
            best_infection_id = 0
            best_exposure = 0.0

            for (inf_sg_idx, inf_p_val) in enumerate(infector_pressure)
                if inf_p_val <= 0.0
                    continue
                end
                cm_r = min(sg_idx, size(contact_matrix, 1))
                cm_c = min(inf_sg_idx, size(contact_matrix, 2))
                cm_val = contact_matrix[cm_r, cm_c]
                exposure = cm_val * inf_p_val * processed_beta * delta_time

                total_exposure += exposure
                if exposure > best_exposure
                    best_exposure = exposure
                    # Pick representative infector from that subgroup
                    for ip in group.subgroups[inf_sg_idx].people
                        if haskey(infectors, ip.id)
                            best_infector_id = ip.id
                            best_infection_id = infectors[ip.id].infection_id
                            break
                        end
                    end
                end
            end

            # Poisson approximation: P(infected) = 1 - exp(-λ)
            if total_exposure > 0.0 && rand() < 1.0 - exp(-total_exposure)
                push!(infected_ids, p.id)
                push!(infection_ids, best_infection_id)
            end
        end
    end

    return infected_ids, infection_ids, group_size
end
