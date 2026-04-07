# Geography in June.jl


- [Exploring Geography](#exploring-geography)
  - [Creating Areas](#creating-areas)
  - [Creating Super Areas](#creating-super-areas)
  - [Creating Regions](#creating-regions)
  - [Adding People to Areas](#adding-people-to-areas)
  - [Geographic Hierarchy Summary](#geographic-hierarchy-summary)
  - [Collections](#collections)

# Exploring Geography

June.jl models England using a three-level geographic hierarchy based on
ONS data:

- **Region**: Coarsest level (e.g., “North East”, “London”)
- **SuperArea**: Middle Super Output Areas (MSOAs)
- **Area**: Output Areas (OAs) — finest resolution

## Creating Areas

An `Area` is the finest geographic unit, defined by a name and
coordinates (latitude, longitude).

``` julia
using June

a1 = Area(; name="E00042673", coordinates=(54.970, -1.610))
a2 = Area(; name="E00042674", coordinates=(54.975, -1.605))
a3 = Area(; name="E00042675", coordinates=(54.968, -1.615))
a4 = Area(; name="E00042676", coordinates=(54.980, -1.620))
println("Created $(4) areas:")
for a in [a1, a2, a3, a4]
    println("  $(a.name) at $(a.coordinates)")
end
```

    Created 4 areas:
      E00042673 at (54.97, -1.61)
      E00042674 at (54.975, -1.605)
      E00042675 at (54.968, -1.615)
      E00042676 at (54.98, -1.62)

## Creating Super Areas

A `SuperArea` groups multiple `Area`s together, corresponding to Middle
Super Output Areas (MSOAs).

``` julia
sa1 = SuperArea(; name="E02004940", coordinates=(54.975, -1.615))
push!(sa1.areas, a1)
push!(sa1.areas, a2)

sa2 = SuperArea(; name="E02004941", coordinates=(54.972, -1.618))
push!(sa2.areas, a3)
push!(sa2.areas, a4)

println("SuperArea $(sa1.name): $(length(sa1.areas)) areas")
for a in sa1.areas
    println("  └─ $(a.name)")
end
println("SuperArea $(sa2.name): $(length(sa2.areas)) areas")
for a in sa2.areas
    println("  └─ $(a.name)")
end
```

    SuperArea E02004940: 2 areas
      └─ E00042673
      └─ E00042674
    SuperArea E02004941: 2 areas
      └─ E00042675
      └─ E00042676

## Creating Regions

A `Region` groups multiple `SuperArea`s, corresponding to broad
geographic regions.

``` julia
region = Region(; name="North East")
push!(region.super_areas, sa1)
push!(region.super_areas, sa2)

println("Region: $(region.name)")
println("  Super areas: $(length(region.super_areas))")
total_areas = sum(length(sa.areas) for sa in region.super_areas)
println("  Total areas: $(total_areas)")
```

    Region: North East
      Super areas: 2
      Total areas: 4

## Adding People to Areas

People can be assigned to areas to model spatial population
distribution.

``` julia
p1 = Person(; sex='m', age=35)
p2 = Person(; sex='f', age=32)
p3 = Person(; sex='m', age=8)

add!(a1, p1)
add!(a1, p2)
add!(a1, p3)

println("Area $(a1.name) has $(length(a1.people)) residents:")
for p in a1.people
    println("  Person id=$(p.id), sex=$(p.sex), age=$(p.age)")
end
```

    Area E00042673 has 3 residents:
      Person id=1, sex=m, age=35
      Person id=2, sex=f, age=32
      Person id=3, sex=m, age=8

## Geographic Hierarchy Summary

``` julia
println("Geographic Hierarchy")
println("====================")
println("Region: $(region.name)")
for sa in region.super_areas
    println("  └─ SuperArea: $(sa.name) @ $(sa.coordinates)")
    for a in sa.areas
        println("       └─ Area: $(a.name) @ $(a.coordinates) [$(length(a.people)) people]")
    end
end
```

    Geographic Hierarchy
    ====================
    Region: North East
      └─ SuperArea: E02004940 @ (54.975, -1.615)
           └─ Area: E00042673 @ (54.97, -1.61) [3 people]
           └─ Area: E00042674 @ (54.975, -1.605) [0 people]
      └─ SuperArea: E02004941 @ (54.972, -1.618)
           └─ Area: E00042675 @ (54.968, -1.615) [0 people]
           └─ Area: E00042676 @ (54.98, -1.62) [0 people]

## Collections

June.jl provides collection types (`Areas`, `SuperAreas`, `Regions`) for
managing geographic units with lookup by ID or name.

``` julia
areas_coll = Areas([a1, a2, a3, a4])
println("Areas collection: $(length(areas_coll.members)) members")
println("Lookup by id $(a2.id): $(get_from_id(areas_coll, a2.id).name)")
```

    Areas collection: 4 members
    Lookup by id 2: E00042674
