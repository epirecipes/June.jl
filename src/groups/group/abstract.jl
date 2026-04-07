# ============================================================================
# Abstract group hierarchy
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

"""
    AbstractGroup

Base type for all group-like containers in the simulation.

Concrete subtypes must implement `people(g)` to return their collection
of `Person` references.  Default filtering methods (`susceptible`,
`infected`, `recovered`, etc.) are provided in terms of `people`.
"""
abstract type AbstractGroup end

# ── Interface (concrete types must implement) ────────────────────────────

"""Return the vector of people belonging to this group."""
function people end

# ── Default implementations ──────────────────────────────────────────────

"""People who are alive and not currently infected."""
susceptible(g::AbstractGroup) =
    filter(p -> !is_infected(p) && !p.dead, people(g))

"""People who currently carry an infection."""
infected(g::AbstractGroup) =
    filter(p -> is_infected(p), people(g))

"""People who are alive and no longer infected (simplified proxy for recovered)."""
recovered_people(g::AbstractGroup) =
    filter(p -> !p.dead && !is_infected(p), people(g))

"""People who are in a hospital medical-facility subgroup."""
in_hospital(g::AbstractGroup) =
    filter(p -> is_hospitalised(p), people(g))

"""People flagged as dead."""
dead_people(g::AbstractGroup) =
    filter(p -> p.dead, people(g))

"""Number of people in the group."""
Base.length(g::AbstractGroup) = length(people(g))

"""Convenience size aliases."""
size_susceptible(g::AbstractGroup) = length(susceptible(g))
size_infected(g::AbstractGroup)    = length(infected(g))
size_recovered(g::AbstractGroup)   = length(recovered_people(g))

"""True when the group has at least one person."""
contains_people(g::AbstractGroup) = length(g) > 0
