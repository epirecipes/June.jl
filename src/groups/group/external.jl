# ============================================================================
# External group / subgroup placeholders for cross-domain (MPI) simulations
#
# These lightweight types carry only identity information — no actual person
# data — so that agents can reference groups that live on another process.
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

# ── ExternalSubgroup ─────────────────────────────────────────────────────

mutable struct ExternalSubgroup
    group::Any           # parent ExternalGroup
    subgroup_type::Int
    people::Vector{Person}
end

ExternalSubgroup(group, subgroup_type::Int) =
    ExternalSubgroup(group, subgroup_type, Person[])

spec(esg::ExternalSubgroup) =
    esg.group === nothing ? "unknown" : esg.group.spec

clear!(::ExternalSubgroup) = nothing   # no-op

function Base.show(io::IO, esg::ExternalSubgroup)
    print(io, "ExternalSubgroup(type=$(esg.subgroup_type))")
end

# ── ExternalGroup ────────────────────────────────────────────────────────

mutable struct ExternalGroup
    id::Int
    spec::String
    domain_id::Int
    subgroups::Vector{ExternalSubgroup}
    external::Bool
end

function ExternalGroup(id::Int, spec::String, domain_id::Int;
                       n_subgroups::Int = 0)
    subgroups = [ExternalSubgroup(nothing, i) for i in 1:n_subgroups]
    g = ExternalGroup(id, spec, domain_id, subgroups, true)
    for sg in g.subgroups
        sg.group = g
    end
    return g
end

clear!(::ExternalGroup) = nothing   # no-op

function get_leisure_subgroup(eg::ExternalGroup, ::Person, subgroup_type::Int)
    return ExternalSubgroup(eg, subgroup_type)
end

function Base.show(io::IO, eg::ExternalGroup)
    print(io, "ExternalGroup(id=$(eg.id), spec=\"$(eg.spec)\", domain=$(eg.domain_id))")
end
