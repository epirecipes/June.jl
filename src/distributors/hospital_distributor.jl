# ---------------------------------------------------------------------------
# HospitalDistributor — assign medics and link closest hospitals
# ---------------------------------------------------------------------------

struct HospitalDistributor
    hospitals::Any
end

"""
    hospital_distributor_from_file(hospitals) -> HospitalDistributor
"""
function hospital_distributor_from_file(hospitals)
    return HospitalDistributor(hospitals)
end

"""
    distribute_medics!(hd::HospitalDistributor, super_areas)

Assign healthcare workers to hospitals.
"""
function distribute_medics!(hd::HospitalDistributor, super_areas)
    isnothing(hd.hospitals) && return
    isnothing(super_areas) && return

    for sa in super_areas.members
        sa.external && continue
        for worker in sa.workers
            worker.dead && continue
            worker.sector == "Q" || continue  # health sector code
            !isnothing(worker.subgroups.primary_activity) && continue

            if !isempty(sa.closest_hospitals)
                hospital = sa.closest_hospitals[1]
                add!(hospital, worker)
            end
        end
    end
end

"""
    assign_closest_hospitals!(hd::HospitalDistributor, super_areas)

Set the `closest_hospitals` list for each super area based on proximity.
"""
function assign_closest_hospitals!(hd::HospitalDistributor, super_areas)
    isnothing(hd.hospitals) && return
    isnothing(super_areas) && return

    hospital_coords = Tuple{Float64,Float64}[]
    hospital_list   = []
    for h in hd.hospitals.members
        if !isnothing(h.group.area)
            push!(hospital_coords, h.group.area.coordinates)
            push!(hospital_list, h)
        end
    end
    isempty(hospital_coords) && return

    for sa in super_areas.members
        sa.external && continue
        # Simple nearest-hospital assignment by Euclidean distance
        dists = [sqrt((sa.coordinates[1] - hc[1])^2 +
                      (sa.coordinates[2] - hc[2])^2)
                 for hc in hospital_coords]
        order = sortperm(dists)
        n_closest = min(5, length(order))
        sa.closest_hospitals = [hospital_list[order[i]] for i in 1:n_closest]
    end
end
