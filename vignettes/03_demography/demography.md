# Demography in June.jl


- [People and Populations](#people-and-populations)
  - [Creating People](#creating-people)
  - [Building a Population](#building-a-population)
  - [Programmatic Population
    Generation](#programmatic-population-generation)
  - [Age Distribution](#age-distribution)
  - [Sex Ratio](#sex-ratio)
  - [Person Attributes](#person-attributes)
  - [Population Lookup](#population-lookup)

# People and Populations

June.jl represents individuals as `Person` agents with demographic
attributes. This vignette shows how to create people, build populations,
and inspect their properties.

## Creating People

``` julia
using June

p1 = Person(; sex='m', age=5)
p2 = Person(; sex='f', age=25)
p3 = Person(; sex='m', age=45)
p4 = Person(; sex='f', age=70, comorbidity="diabetes")
p5 = Person(; sex='m', age=85)
println("Created 5 people:")
for p in [p1, p2, p3, p4, p5]
    cm = isnothing(p.comorbidity) ? "" : " ($(p.comorbidity))"
    println("  id=$(p.id), sex=$(p.sex), age=$(p.age)$cm")
end
```

    Created 5 people:
      id=1, sex=m, age=5
      id=2, sex=f, age=25
      id=3, sex=m, age=45
      id=4, sex=f, age=70 (diabetes)
      id=5, sex=m, age=85

## Building a Population

A `Population` is a managed collection of `Person` objects with a lookup
dictionary.

``` julia
pop = Population()
for p in [p1, p2, p3, p4, p5]
    add!(pop, p)
end
println("Population size: $(length(members(pop)))")
```

    Population size: 5

## Programmatic Population Generation

We can generate larger synthetic populations programmatically.

``` julia
using Random
Random.seed!(42)

pop_large = Population()
sexes = ['m', 'f']
for i in 1:100
    s = sexes[rand(1:2)]
    a = rand(0:99)
    p = Person(; sex=s, age=a)
    add!(pop_large, p)
end
println("Large population: $(length(members(pop_large))) people")
```

    Large population: 100 people

## Age Distribution

``` julia
ages = [p.age for p in members(pop_large)]

# Compute histogram bins
bins = Dict{String, Int}()
for a in ages
    bracket = "$(div(a, 10)*10)-$(div(a, 10)*10 + 9)"
    bins[bracket] = get(bins, bracket, 0) + 1
end
sorted_bins = sort(collect(bins), by=x -> parse(Int, split(x[1], "-")[1]))

println("Age Distribution (n=$(length(ages)))")
println("─" ^ 40)
for (bracket, count) in sorted_bins
    bar = repeat("█", count)
    println(rpad(bracket, 8), " | ", rpad(count, 4), bar)
end
```

    Age Distribution (n=100)
    ────────────────────────────────────────
    0-9      | 8   ████████
    10-19    | 12  ████████████
    20-29    | 9   █████████
    30-39    | 7   ███████
    40-49    | 15  ███████████████
    50-59    | 9   █████████
    60-69    | 15  ███████████████
    70-79    | 9   █████████
    80-89    | 8   ████████
    90-99    | 8   ████████

## Sex Ratio

``` julia
n_female = count(p -> p.sex == 'f', members(pop_large))
n_male = count(p -> p.sex == 'm', members(pop_large))
n_total = length(members(pop_large))
println("Female: $n_female ($(round(100*n_female/n_total, digits=1))%)")
println("Male:   $n_male ($(round(100*n_male/n_total, digits=1))%)")
```

    Female: 48 (48.0%)
    Male:   52 (52.0%)

## Person Attributes

Each person carries demographic and simulation state fields.

``` julia
p = Person(; sex='f', age=42, comorbidity="lung_disease")
println("Core attributes:")
println("  id:          $(p.id)")
println("  sex:         $(p.sex)")
println("  age:         $(p.age)")
println("  comorbidity: $(p.comorbidity)")
println("  dead:        $(p.dead)")
println("  busy:        $(p.busy)")
println("  infected:    $(is_infected(p))")
```

    Core attributes:
      id:          106
      sex:         f
      age:         42
      comorbidity: lung_disease
      dead:        false
      busy:        false
      infected:    false

## Population Lookup

``` julia
target_id = p3.id
found = get_from_id(pop, target_id)
println("Looked up person id=$(target_id): sex=$(found.sex), age=$(found.age)")
```

    Looked up person id=3: sex=m, age=45
