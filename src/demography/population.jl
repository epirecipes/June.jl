"""
    Population

A collection of `Person` agents with O(1) ID-based lookup.
Supports iteration, indexing, and standard collection operations.
Mirrors the Python `Population` class.
"""
mutable struct Population
    people::Vector{Person}
    people_dict::Dict{Int, Person}
end

"""Create an empty population."""
Population() = Population(Person[], Dict{Int, Person}())

"""Create a population from a vector of persons."""
function Population(people::Vector{Person})
    d = Dict{Int, Person}(p.id => p for p in people)
    return Population(copy(people), d)
end

# ── AbstractVector-style interface ───────────────────────────────────────

Base.length(pop::Population) = length(pop.people)
Base.size(pop::Population) = (length(pop.people),)
Base.isempty(pop::Population) = isempty(pop.people)
Base.iterate(pop::Population) = iterate(pop.people)
Base.iterate(pop::Population, state) = iterate(pop.people, state)
Base.getindex(pop::Population, i::Int) = pop.people[i]
Base.lastindex(pop::Population) = lastindex(pop.people)
Base.eltype(::Type{Population}) = Person

# ── Mutation ─────────────────────────────────────────────────────────────

"""Add a person to the population."""
function Base.push!(pop::Population, p::Person)
    push!(pop.people, p)
    pop.people_dict[p.id] = p
    return pop
end

"""Alias for `push!` to match the Python API."""
add!(pop::Population, p::Person) = push!(pop, p)

"""Remove a person from the population."""
function remove!(pop::Population, p::Person)
    delete!(pop.people_dict, p.id)
    idx = findfirst(x -> x === p, pop.people)
    if idx !== nothing
        deleteat!(pop.people, idx)
    end
    return pop
end

"""Add multiple persons to the population."""
function extend!(pop::Population, people)
    for p in people
        push!(pop, p)
    end
    return pop
end

# ── Queries ──────────────────────────────────────────────────────────────

"""Look up a person by ID. Throws `KeyError` if not found."""
get_from_id(pop::Population, id::Int) = pop.people_dict[id]

"""Return the underlying people vector."""
members(pop::Population) = pop.people

"""Total number of people (alias for `length`)."""
total_people(pop::Population) = length(pop)

"""Return a vector of currently infected persons."""
infected(pop::Population) = filter(is_infected, pop.people)

"""Return a vector of dead persons."""
dead_people(pop::Population) = filter(p -> p.dead, pop.people)

"""Return a vector of vaccinated persons."""
vaccinated(pop::Population) = filter(p -> p.vaccinated !== nothing, pop.people)

# ── Display ──────────────────────────────────────────────────────────────

function Base.show(io::IO, pop::Population)
    n = length(pop)
    ni = length(infected(pop))
    print(io, "Population($n people, $ni infected)")
end
