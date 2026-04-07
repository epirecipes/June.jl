# Demography in JUNE (Python)


- [People and Populations](#people-and-populations)
  - [Setup](#setup)
  - [Creating People](#creating-people)
  - [Programmatic Population
    Generation](#programmatic-population-generation)
  - [Age Distribution](#age-distribution)
  - [Sex Ratio](#sex-ratio)
  - [Person Attributes](#person-attributes)

# People and Populations

JUNE represents individuals as `Person` agents with demographic
attributes. This vignette shows how to create people, build collections,
and inspect their properties.

## Setup

``` python
import sys, types
fake_turtle = types.ModuleType('turtle')
fake_turtle.home = lambda: None
sys.modules['turtle'] = fake_turtle
```

## Creating People

``` python
from june.demography import Person

p1 = Person.from_attributes(sex='m', age=5)
p2 = Person.from_attributes(sex='f', age=25)
p3 = Person.from_attributes(sex='m', age=45)
p4 = Person.from_attributes(sex='f', age=70)
p5 = Person.from_attributes(sex='m', age=85)
print("Created 5 people:")
for p in [p1, p2, p3, p4, p5]:
    print(f"  id={p.id}, sex={p.sex}, age={p.age}")
```

    No --data argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/June.jl/vignettes/03_demography/python/data
    No --configs argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/JUNE/june/configs

    Created 5 people:
      id=0, sex=m, age=5
      id=1, sex=f, age=25
      id=2, sex=m, age=45
      id=3, sex=f, age=70
      id=4, sex=m, age=85

## Programmatic Population Generation

``` python
import random
random.seed(42)

people = []
sexes = ['m', 'f']
for i in range(100):
    s = random.choice(sexes)
    a = random.randint(0, 99)
    p = Person.from_attributes(sex=s, age=a)
    people.append(p)
print(f"Generated population: {len(people)} people")
```

    Generated population: 100 people

## Age Distribution

``` python
ages = [p.age for p in people]
bins = {}
for a in ages:
    bracket = f"{(a // 10) * 10}-{(a // 10) * 10 + 9}"
    bins[bracket] = bins.get(bracket, 0) + 1
sorted_bins = sorted(bins.items(), key=lambda x: int(x[0].split("-")[0]))

print(f"Age Distribution (n={len(ages)})")
print("─" * 40)
for bracket, count in sorted_bins:
    bar = "█" * count
    print(f"{bracket:<8} | {count:<4}{bar}")
```

    Age Distribution (n=100)
    ────────────────────────────────────────
    0-9      | 7   ███████
    10-19    | 17  █████████████████
    20-29    | 9   █████████
    30-39    | 5   █████
    40-49    | 10  ██████████
    50-59    | 5   █████
    60-69    | 7   ███████
    70-79    | 15  ███████████████
    80-89    | 14  ██████████████
    90-99    | 11  ███████████

## Sex Ratio

``` python
n_female = sum(1 for p in people if p.sex == 'f')
n_male = sum(1 for p in people if p.sex == 'm')
n_total = len(people)
print(f"Female: {n_female} ({100*n_female/n_total:.1f}%)")
print(f"Male:   {n_male} ({100*n_male/n_total:.1f}%)")
```

    Female: 49 (49.0%)
    Male:   51 (51.0%)

## Person Attributes

``` python
p = Person.from_attributes(sex='f', age=42)
print("Core attributes:")
print(f"  id:       {p.id}")
print(f"  sex:      {p.sex}")
print(f"  age:      {p.age}")
print(f"  dead:     {p.dead}")
print(f"  infected: {p.infected}")
```

    Core attributes:
      id:       105
      sex:      f
      age:      42
      dead:     False
      infected: False
