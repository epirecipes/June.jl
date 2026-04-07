# ---------------------------------------------------------------------------
# CompanyDistributor — assign remaining workers to companies
# ---------------------------------------------------------------------------

struct CompanyDistributor end

"""
    distribute_adults_to_companies!(cd::CompanyDistributor, super_areas)

Assign remaining workers (those not placed in hospitals, schools, etc.)
to companies in their super area.
"""
function distribute_adults_to_companies!(cd::CompanyDistributor, super_areas)
    isnothing(super_areas) && return

    for sa in super_areas.members
        sa.external && continue
        isempty(sa.companies) && continue

        company_idx = 1
        for worker in sa.workers
            worker.dead && continue
            # Skip people already placed in a primary activity
            !isnothing(worker.subgroups.primary_activity) && continue

            company = sa.companies[company_idx]
            add!(company, worker)
            company_idx = mod1(company_idx + 1, length(sa.companies))
        end
    end
end
