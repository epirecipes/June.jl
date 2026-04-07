# June.jl Quickstart


- [Getting Started with June.jl](#getting-started-with-junejl)
  - [Setup](#setup)
  - [Creating People](#creating-people)
  - [Placing People in a Household](#placing-people-in-a-household)
  - [Transmission Curve](#transmission-curve)
  - [Building a Small Synthetic
    World](#building-a-small-synthetic-world)
  - [Immunity Overview](#immunity-overview)
  - [Summary](#summary)

# Getting Started with June.jl

This vignette provides a quick overview of the core building blocks in
June.jl: people, places, disease transmission, and immunity.

## Setup

``` julia
using June
```

## Creating People

`Person` is the fundamental agent. Each person has an age, sex, and
optional attributes.

``` julia
p1 = Person(; sex='m', age=30)
p2 = Person(; sex='f', age=25)
p3 = Person(; sex='m', age=70, comorbidity="diabetes")
println("Person 1: sex=$(p1.sex), age=$(p1.age)")
println("Person 2: sex=$(p2.sex), age=$(p2.age)")
println("Person 3: sex=$(p3.sex), age=$(p3.age), comorbidity=$(p3.comorbidity)")
```

    Person 1: sex=m, age=30
    Person 2: sex=f, age=25
    Person 3: sex=m, age=70, comorbidity=diabetes

## Placing People in a Household

Households are the most basic group. Use `add!` to assign people.

``` julia
h = Household()
add!(h, p1)
add!(h, p2)
println("Household has $(n_residents(h)) residents")
println("People: $(["sex=$(p.sex), age=$(p.age)" for p in people(h)])")
```

    Household has 2 residents
    People: ["sex=m, age=30", "sex=f, age=25"]

## Transmission Curve

The `TransmissionGamma` profile models how infectiousness varies over
time since infection.

``` julia
tg = TransmissionGamma(0.3, 1.56, 0.53, -2.12)
println("Gamma transmission profile (max_infectiousness=0.3, shape=1.56, rate=0.53, shift=-2.12)")
println()
println("Day  | Probability")
println("-----|------------")
for day in 0:2:20
    update_infection_probability!(tg, Float64(day))
    bar = repeat("█", round(Int, tg.probability * 200))
    println(lpad(day, 4), " | ", rpad(round(tg.probability, digits=6), 10), " ", bar)
end
```

    Gamma transmission profile (max_infectiousness=0.3, shape=1.56, rate=0.53, shift=-2.12)

    Day  | Probability
    -----|------------
       0 | 0.25218    ██████████████████████████████████████████████████
       2 | 0.126751   █████████████████████████
       4 | 0.054807   ███████████
       6 | 0.022246   ████
       8 | 0.008719   ██
      10 | 0.003342   █
      12 | 0.001261   
      14 | 0.000471   
      16 | 0.000174   
      18 | 6.4e-5     
      20 | 2.3e-5     

## Building a Small Synthetic World

We can manually construct a geographic hierarchy and populate it with
people and groups.

``` julia
# Geography
a1 = Area(; name="E00042673", coordinates=(54.97, -1.61))
a2 = Area(; name="E00042674", coordinates=(54.975, -1.605))
sa = SuperArea(; name="E02004940", coordinates=(54.975, -1.615))
push!(sa.areas, a1)
push!(sa.areas, a2)
r = Region(; name="North East")
push!(r.super_areas, sa)

println("Region: $(r.name)")
println("  SuperArea: $(sa.name) with $(length(sa.areas)) areas")
for a in sa.areas
    println("    Area: $(a.name) at $(a.coordinates)")
end
```

    Region: North East
      SuperArea: E02004940 with 2 areas
        Area: E00042673 at (54.97, -1.61)
        Area: E00042674 at (54.975, -1.605)

``` julia
# Create a population and assign to groups
pop = Population()
people_list = Person[]
for i in 1:5
    p = Person(; sex=i % 2 == 0 ? 'f' : 'm', age=20 + i * 10)
    add!(pop, p)
    push!(people_list, p)
end
println("Population size: $(length(members(pop)))")

# Household
h2 = Household()
add!(h2, people_list[1])
add!(h2, people_list[2])
println("Household: $(n_residents(h2)) residents")

# School
s = School((54.97, -1.61), 200, 5, 18, "secondary")
add!(s, people_list[3])
println("School sector=$(s.sector), pupils=$(length(people(s)))")

# Company
c = Company(; sector="tech", n_workers_max=50)
add!(c, people_list[4])
println("Company sector=$(c.sector), workers=$(length(people(c)))")
```

    Population size: 5
    Household: 2 residents
    School sector=secondary, pupils=1
    Company sector=tech, workers=1

## Immunity Overview

Every person has an `Immunity` object tracking susceptibility to each
pathogen (by infection ID).

``` julia
imm = Immunity()
println("Default susceptibility (infection 0): $(get_susceptibility(imm, 0))")
imm.susceptibility_dict[0] = 0.48
println("After vaccination: $(get_susceptibility(imm, 0))")
```

    Default susceptibility (infection 0): 1.0
    After vaccination: 0.48

## Summary

June.jl provides composable building blocks — `Person`, geographic units
(`Area`, `SuperArea`, `Region`), groups (`Household`, `School`,
`Company`), and epidemiological models (`TransmissionGamma`, `Immunity`)
— that can be assembled into large-scale agent-based simulations.
