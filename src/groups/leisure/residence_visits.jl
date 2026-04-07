# ---------------------------------------------------------------------------
# ResidenceVisitsDistributor — link households for mutual visits
# ---------------------------------------------------------------------------

struct ResidenceVisitsDistributor
    household_links::Dict{Int, Vector{Int}}   # household_id → linked household_ids
    care_home_links::Dict{Int, Vector{Int}}
end

function ResidenceVisitsDistributor()
    return ResidenceVisitsDistributor(Dict{Int,Vector{Int}}(), Dict{Int,Vector{Int}}())
end

"""
    link_households!(rvd::ResidenceVisitsDistributor, households)

Randomly pair 2–4 households per household for visit contacts.
"""
function link_households!(rvd::ResidenceVisitsDistributor, households)
    isnothing(households) && return
    ids = [h.group.id for h in households.members]
    isempty(ids) && return

    for h in households.members
        n_links = rand(2:4)
        candidates = filter(!=(h.group.id), ids)
        n_links = min(n_links, length(candidates))
        n_links == 0 && continue
        linked = sample(candidates, n_links; replace=false)
        rvd.household_links[h.group.id] = linked
    end
end
