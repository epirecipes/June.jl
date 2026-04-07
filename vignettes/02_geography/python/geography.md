# Geography in JUNE (Python)


- [Exploring Geography](#exploring-geography)
  - [Setup](#setup)
  - [Creating Areas](#creating-areas)
  - [Creating Super Areas](#creating-super-areas)
  - [Adding People to Areas](#adding-people-to-areas)
  - [Geographic Hierarchy Summary](#geographic-hierarchy-summary)

# Exploring Geography

JUNE models England using a three-level geographic hierarchy based on
ONS data:

- **Region**: Coarsest level (e.g., “North East”, “London”)
- **SuperArea**: Middle Super Output Areas (MSOAs)
- **Area**: Output Areas (OAs) — finest resolution

## Setup

``` python
import sys, types
fake_turtle = types.ModuleType('turtle')
fake_turtle.home = lambda: None
sys.modules['turtle'] = fake_turtle
```

## Creating Areas

An `Area` is the finest geographic unit, defined by a name and
coordinates.

``` python
from june.geography import Area, SuperArea

a1 = Area(name="E00042673", super_area=None, coordinates=[54.970, -1.610])
a2 = Area(name="E00042674", super_area=None, coordinates=[54.975, -1.605])
a3 = Area(name="E00042675", super_area=None, coordinates=[54.968, -1.615])
a4 = Area(name="E00042676", super_area=None, coordinates=[54.980, -1.620])
print(f"Created 4 areas:")
for a in [a1, a2, a3, a4]:
    print(f"  {a.name} at {a.coordinates}")
```

    No --data argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/June.jl/vignettes/02_geography/python/data
    No --configs argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/JUNE/june/configs

    Created 4 areas:
      E00042673 at [54.97, -1.61]
      E00042674 at [54.975, -1.605]
      E00042675 at [54.968, -1.615]
      E00042676 at [54.98, -1.62]

## Creating Super Areas

A `SuperArea` groups multiple `Area`s together.

``` python
sa1 = SuperArea(name="E02004940", areas=[a1, a2], coordinates=[54.975, -1.615])
sa2 = SuperArea(name="E02004941", areas=[a3, a4], coordinates=[54.972, -1.618])

print(f"SuperArea {sa1.name}: {len(sa1.areas)} areas")
for a in sa1.areas:
    print(f"  └─ {a.name}")
print(f"SuperArea {sa2.name}: {len(sa2.areas)} areas")
for a in sa2.areas:
    print(f"  └─ {a.name}")
```

    SuperArea E02004940: 2 areas
      └─ E00042673
      └─ E00042674
    SuperArea E02004941: 2 areas
      └─ E00042675
      └─ E00042676

## Adding People to Areas

``` python
from june.demography import Person

p1 = Person.from_attributes(sex='m', age=35)
p2 = Person.from_attributes(sex='f', age=32)
p3 = Person.from_attributes(sex='m', age=8)

a1.add(p1)
a1.add(p2)
a1.add(p3)

print(f"Area {a1.name} has {len(a1.people)} residents:")
for p in a1.people:
    print(f"  Person: sex={p.sex}, age={p.age}")
```

    Area E00042673 has 3 residents:
      Person: sex=m, age=35
      Person: sex=f, age=32
      Person: sex=m, age=8

## Geographic Hierarchy Summary

``` python
print("Geographic Hierarchy")
print("=" * 40)
for sa in [sa1, sa2]:
    print(f"  └─ SuperArea: {sa.name} @ {sa.coordinates}")
    for a in sa.areas:
        n = len(a.people) if hasattr(a, 'people') and a.people else 0
        print(f"       └─ Area: {a.name} @ {a.coordinates} [{n} people]")
```

    Geographic Hierarchy
    ========================================
      └─ SuperArea: E02004940 @ [54.975, -1.615]
           └─ Area: E00042673 @ [54.97, -1.61] [3 people]
           └─ Area: E00042674 @ [54.975, -1.605] [0 people]
      └─ SuperArea: E02004941 @ [54.972, -1.618]
           └─ Area: E00042675 @ [54.968, -1.615] [0 people]
           └─ Area: E00042676 @ [54.98, -1.62] [0 people]
