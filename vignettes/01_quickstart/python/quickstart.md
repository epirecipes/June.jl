# JUNE (Python) Quickstart


- [Getting Started with JUNE
  (Python)](#getting-started-with-june-python)
  - [Setup](#setup)
  - [Creating People](#creating-people)
  - [Placing People in a Household](#placing-people-in-a-household)
  - [Transmission Curve](#transmission-curve)
  - [Building a Small Synthetic
    World](#building-a-small-synthetic-world)
  - [Immunity Overview](#immunity-overview)
  - [Summary](#summary)

# Getting Started with JUNE (Python)

This vignette provides a quick overview of the core building blocks in
Python JUNE: people, places, disease transmission, and immunity.

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

p1 = Person.from_attributes(sex='m', age=30)
p2 = Person.from_attributes(sex='f', age=25)
p3 = Person.from_attributes(sex='m', age=70)
print(f"Person 1: sex={p1.sex}, age={p1.age}")
print(f"Person 2: sex={p2.sex}, age={p2.age}")
print(f"Person 3: sex={p3.sex}, age={p3.age}")
```

    No --data argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/June.jl/vignettes/01_quickstart/python/data
    No --configs argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/JUNE/june/configs

    Person 1: sex=m, age=30
    Person 2: sex=f, age=25
    Person 3: sex=m, age=70

## Placing People in a Household

``` python
from june.groups import Household

h = Household()
h.add(p1)
h.add(p2)
print(f"Household has {len(h.people)} residents")
for p in h.people:
    print(f"  Person: sex={p.sex}, age={p.age}")
```

    Household has 2 residents
      Person: sex=f, age=25
      Person: sex=m, age=30

## Transmission Curve

The `TransmissionGamma` profile models how infectiousness varies over
time since infection.

``` python
from june.epidemiology.infection.transmission import TransmissionGamma

tg = TransmissionGamma(max_infectiousness=0.3, shape=1.56, rate=0.53, shift=-2.12)
print("Gamma transmission profile (max_infectiousness=0.3, shape=1.56, rate=0.53, shift=-2.12)")
print()
print(f"{'Day':>4} | {'Probability':<12} | Profile")
print("-" * 5 + "|" + "-" * 14 + "|" + "-" * 40)
for day in range(0, 21, 2):
    tg.update_infection_probability(float(day))
    bar = "█" * int(tg.probability * 200)
    print(f"{day:4d} | {tg.probability:<12.6f} | {bar}")
```

    Gamma transmission profile (max_infectiousness=0.3, shape=1.56, rate=0.53, shift=-2.12)

     Day | Probability  | Profile
    -----|--------------|----------------------------------------
       0 | 0.062023     | ████████████
       2 | 0.031174     | ██████
       4 | 0.013480     | ██
       6 | 0.005471     | █
       8 | 0.002144     | 
      10 | 0.000822     | 
      12 | 0.000310     | 
      14 | 0.000116     | 
      16 | 0.000043     | 
      18 | 0.000016     | 
      20 | 0.000006     | 

## Building a Small Synthetic World

``` python
from june.geography import Area, SuperArea

a1 = Area(name="E00042673", super_area=None, coordinates=[54.97, -1.61])
a2 = Area(name="E00042674", super_area=None, coordinates=[54.975, -1.605])
sa = SuperArea(name="E02004940", areas=[a1, a2], coordinates=[54.975, -1.615])

print(f"SuperArea: {sa.name} with {len(sa.areas)} areas")
for a in sa.areas:
    print(f"  Area: {a.name} at {a.coordinates}")
```

    SuperArea: E02004940 with 2 areas
      Area: E00042673 at [54.97, -1.61]
      Area: E00042674 at [54.975, -1.605]

``` python
from june.groups import Household
from june.groups.school import School
from june.groups.company import Company

# Household
h2 = Household()
h2.add(Person.from_attributes(sex='m', age=40))
h2.add(Person.from_attributes(sex='f', age=38))
print(f"Household: {len(h2.people)} residents")

# Company
c = Company(sector="tech", n_workers_max=50)
c.add(Person.from_attributes(sex='m', age=45))
print(f"Company sector={c.sector}, workers={c.n_workers}")
```

    Household: 2 residents
    Company sector=tech, workers=1

## Immunity Overview

``` python
from june.epidemiology.infection import Immunity

imm = Immunity()
print(f"Default susceptibility (infection 0): {imm.get_susceptibility(0)}")
imm.susceptibility_dict[0] = 0.48
print(f"After vaccination: {imm.get_susceptibility(0)}")
```

    Default susceptibility (infection 0): 1.0
    After vaccination: 0.48

## Summary

Python JUNE provides the same composable building blocks — `Person`,
geographic units (`Area`, `SuperArea`), groups (`Household`, `School`,
`Company`), and epidemiological models (`TransmissionGamma`, `Immunity`)
— as its Julia counterpart.
