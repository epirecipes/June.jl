# ---------------------------------------------------------------------------
# CareHomeDistributor — populate care homes with elderly and workers
# ---------------------------------------------------------------------------

struct CareHomeDistributor end

"""
    care_home_distributor_from_file() -> CareHomeDistributor
"""
function care_home_distributor_from_file()
    return CareHomeDistributor()
end

"""
    populate_care_homes!(chd::CareHomeDistributor, super_areas)

Move elderly people (65+) to care homes where capacity allows.
"""
function populate_care_homes!(chd::CareHomeDistributor, super_areas)
    isnothing(super_areas) && return

    for sa in super_areas.members
        sa.external && continue
        for area in sa.areas
            isnothing(area.care_home) && continue
            ch = area.care_home
            for person in area.people
                person.dead && continue
                person.age >= 65 || continue
                !isnothing(person.subgroups.residence) && continue
                add!(ch, person; activity=:residence)
            end
        end
    end
end

"""
    distribute_workers_to_care_homes!(chd::CareHomeDistributor, super_areas)

Assign care workers to care homes.
"""
function distribute_workers_to_care_homes!(chd::CareHomeDistributor, super_areas)
    isnothing(super_areas) && return

    for sa in super_areas.members
        sa.external && continue
        for area in sa.areas
            isnothing(area.care_home) && continue
            ch = area.care_home
            for worker in sa.workers
                worker.dead && continue
                worker.sector == "Q" || continue
                !isnothing(worker.subgroups.primary_activity) && continue
                add!(ch, worker; activity=:primary_activity)
                break  # one worker per care home in simplified version
            end
        end
    end
end
