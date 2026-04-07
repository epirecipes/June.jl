# ---------------------------------------------------------------------------
# WorkerDistributor — assign workers to sectors from census data
# ---------------------------------------------------------------------------

struct WorkerDistributor
    workflow_df::Union{Nothing, DataFrame}  # sector workflow data
end

"""
    worker_distributor_for_super_areas(; area_names) -> WorkerDistributor

Load workflow/sector data from CSV (stub — returns empty distributor).
"""
function worker_distributor_for_super_areas(; area_names=String[])
    return WorkerDistributor(nothing)
end

"""
    distribute_workers!(wd::WorkerDistributor; areas, super_areas, population)

Assign working-age people to sectors based on census employment data.
Sets `person.sector` and `person.work_super_area`.
"""
function distribute_workers!(wd::WorkerDistributor;
                             areas=nothing, super_areas=nothing, population=nothing)
    isnothing(super_areas) && return
    isnothing(population) && return

    for sa in super_areas.members
        sa.external && continue
        for area in sa.areas
            for person in area.people
                # Working-age heuristic: 18–64
                if 18 <= person.age <= 64 && !person.dead
                    person.work_super_area = sa
                    add_worker!(sa, person)
                end
            end
        end
    end
end
