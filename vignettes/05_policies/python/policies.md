# Groups, Interactions, and Policies in JUNE (Python)


- [Groups, Interactions, and
  Policies](#groups-interactions-and-policies)
  - [Setup](#setup)
  - [Households](#households)
  - [Schools](#schools)
  - [Companies](#companies)
  - [Hospitals](#hospitals)
  - [Group Summary](#group-summary)
  - [The Interaction Model](#the-interaction-model)
  - [Policies](#policies)
    - [Social Distancing](#social-distancing)
    - [Stay at Home](#stay-at-home)
    - [Mask Wearing](#mask-wearing)
    - [Shielding](#shielding)
  - [Policy Summary](#policy-summary)

# Groups, Interactions, and Policies

JUNE organises people into **groups** — places where interactions (and
disease transmission) occur. **Policies** modify these interactions
(e.g., social distancing, school closures). This vignette demonstrates
groups, the interaction model, and the policy system.

## Setup

``` python
import sys, types
fake_turtle = types.ModuleType('turtle')
fake_turtle.home = lambda: None
sys.modules['turtle'] = fake_turtle
```

## Households

Households are the most fundamental group.

``` python
from june.demography import Person
from june.groups import Household

p1 = Person.from_attributes(sex='m', age=40)
p2 = Person.from_attributes(sex='f', age=38)
p3 = Person.from_attributes(sex='f', age=12)
p4 = Person.from_attributes(sex='m', age=8)

h = Household()
h.add(p1)
h.add(p2)
h.add(p3)
h.add(p4)

print(f"Household: {len(h.people)} residents")
for p in h.people:
    print(f"  Person: sex={p.sex}, age={p.age}")
```

    No --data argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/June.jl/vignettes/05_policies/python/data
    No --configs argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/JUNE/june/configs

    Household: 4 residents
      Person: sex=f, age=12
      Person: sex=m, age=8
      Person: sex=m, age=40
      Person: sex=f, age=38

## Schools

Schools have a sector, age range, and maximum pupil capacity.

``` python
from june.groups.school import School

school = School(coordinates=[54.97, -1.61], n_pupils_max=300,
                age_min=5, age_max=11, sector="primary")
print(f"School: sector={school.sector}, age_min={school.age_min}, age_max={school.age_max}")
print(f"  Max pupils: {school.n_pupils_max}")

child1 = Person.from_attributes(sex='f', age=7)
child2 = Person.from_attributes(sex='m', age=9)
child3 = Person.from_attributes(sex='f', age=10)
school.add(child1)
school.add(child2)
school.add(child3)
print(f"  Current pupils: {school.n_pupils}")
```

    School: sector=primary, age_min=5, age_max=11
      Max pupils: 300
      Current pupils: 3

## Companies

Companies are workplaces with a sector and maximum worker capacity.

``` python
from june.groups.company import Company

c1 = Company(sector="Q", n_workers_max=20)
c2 = Company(sector="G", n_workers_max=5)

w1 = Person.from_attributes(sex='m', age=30)
w2 = Person.from_attributes(sex='f', age=45)
w3 = Person.from_attributes(sex='m', age=55)
c1.add(w1)
c1.add(w2)
c2.add(w3)

print(f"Company 1: sector={c1.sector}, workers={c1.n_workers}/{c1.n_workers_max}")
print(f"Company 2: sector={c2.sector}, workers={c2.n_workers}/{c2.n_workers_max}")
```

    Company 1: sector=Q, workers=2/20
    Company 2: sector=G, workers=1/5

## Hospitals

``` python
from june.groups.hospital import Hospital

hosp = Hospital(n_beds=100, n_icu_beds=10, trust_code="NT1")
print(f"Hospital: trust_code={hosp.trust_code}")
print(f"  Beds: {hosp.n_beds}, ICU beds: {hosp.n_icu_beds}")
```

    Hospital: trust_code=NT1
      Beds: 100, ICU beds: 10

## Group Summary

``` python
print(f"{'Group Type':<18} | {'Example':<18} | People")
print("─" * 18 + "|" + "─" * 20 + "|" + "─" * 8)
print(f"{'Household':<18} | {'Family home':<18} | {len(h.people)}")
print(f"{'School':<18} | {'Primary school':<18} | {school.n_pupils}")
print(f"{'Company':<18} | {'Sector Q firm':<18} | {c1.n_workers}")
print(f"{'Hospital':<18} | {'NT1 trust':<18} | {hosp.n_beds} beds")
```

    Group Type         | Example            | People
    ──────────────────|────────────────────|────────
    Household          | Family home        | 4
    School             | Primary school     | 3
    Company            | Sector Q firm      | 2
    Hospital           | NT1 trust          | 100 beds

## The Interaction Model

The `Interaction` class controls how disease spreads within groups. It
is parameterised by:

- **`alpha_physical`**: Scaling factor for physical (vs. non-physical)
  contacts
- **`betas`**: Per-group transmission intensities
- **`contact_matrices`**: Contact patterns within subgroups of each
  group type

``` python
import numpy as np

betas = {
    "household": 0.208,
    "school": 0.070,
    "company": 0.371,
    "pub": 0.429,
    "grocery": 0.041,
}

print("Interaction model:")
print(f"  alpha_physical: 2.0")
print(f"  Group betas:")
for g, b in sorted(betas.items(), key=lambda x: -x[1]):
    bar = "█" * int(b * 40)
    print(f"    {g:<12} β={b:<6} {bar}")
```

    Interaction model:
      alpha_physical: 2.0
      Group betas:
        pub          β=0.429  █████████████████
        company      β=0.371  ██████████████
        household    β=0.208  ████████
        school       β=0.07   ██
        grocery      β=0.041  █

## Policies

Policies modify behaviour during a simulation. They are organised into
categories:

- **Individual policies**: Keep people at home (e.g., stay-at-home,
  quarantine, shielding)
- **Interaction policies**: Reduce transmission (e.g., social
  distancing, mask wearing)
- **Leisure policies**: Close or limit leisure venues

### Social Distancing

Social distancing reduces transmission by applying per-group beta
scaling factors.

``` python
from datetime import datetime

# Define a social distancing policy
sd_start = datetime(2020, 3, 23)
sd_end = datetime(2020, 6, 1)
sd_beta_factors = {"school": 0.5, "company": 0.7, "pub": 0.0}

print("Social distancing policy:")
print(f"  Active: {sd_start} to {sd_end}")
print(f"  Beta reductions:")
for g, f in sorted(sd_beta_factors.items()):
    pct = round((1.0 - f) * 100)
    print(f"    {g:<12} factor={f}  ({pct}% reduction)")
```

    Social distancing policy:
      Active: 2020-03-23 00:00:00 to 2020-06-01 00:00:00
      Beta reductions:
        company      factor=0.7  (30% reduction)
        pub          factor=0.0  (100% reduction)
        school       factor=0.5  (50% reduction)

### Stay at Home

A stay-at-home order keeps a fraction of the population at home.

``` python
stay_compliance = 0.85

print("Stay-at-home policy:")
print(f"  Active: {sd_start} to {sd_end}")
print(f"  Compliance: {stay_compliance * 100}%")
```

    Stay-at-home policy:
      Active: 2020-03-23 00:00:00 to 2020-06-01 00:00:00
      Compliance: 85.0%

### Mask Wearing

Mask wearing reduces transmission through face coverings.

``` python
mask_start = datetime(2020, 6, 15)
mask_probability = 0.8
mask_compliance = 0.9
mask_beta_factor = 0.5

print("Mask wearing policy:")
print(f"  Start: {mask_start}")
print(f"  End: indefinite")
print(f"  Mask probability: {mask_probability * 100}%")
print(f"  Compliance: {mask_compliance * 100}%")
print(f"  Beta factor: {mask_beta_factor}")
```

    Mask wearing policy:
      Start: 2020-06-15 00:00:00
      End: indefinite
      Mask probability: 80.0%
      Compliance: 90.0%
      Beta factor: 0.5

### Shielding

Shielding keeps vulnerable (elderly) people at home.

``` python
shield_start = datetime(2020, 3, 23)
shield_end = datetime(2020, 8, 1)
shield_min_age = 70
shield_compliance = 0.85

print("Shielding policy:")
print(f"  Active: {shield_start} to {shield_end}")
print(f"  Min age: {shield_min_age}")
print(f"  Compliance: {shield_compliance * 100}%")
```

    Shielding policy:
      Active: 2020-03-23 00:00:00 to 2020-08-01 00:00:00
      Min age: 70
      Compliance: 85.0%

## Policy Summary

``` python
print("Policy Summary")
print("═" * 66)
print(f"{'Category':<13} | {'Policy':<18} | Key Parameter")
print("─" * 13 + "|" + "─" * 20 + "|" + "─" * 31)
print(f"{'Individual':<13} | {'StayHome':<18} | compliance={stay_compliance}")
print(f"{'Individual':<13} | {'Shielding':<18} | min_age={shield_min_age}, compliance={shield_compliance}")
print(f"{'Interaction':<13} | {'SocialDistancing':<18} | school β×{sd_beta_factors['school']}")
print(f"{'Interaction':<13} | {'MaskWearing':<18} | β×{mask_beta_factor}, prob={mask_probability}")
print("─" * 13 + "|" + "─" * 20 + "|" + "─" * 31)
print()
print("In full JUNE simulations, policies are loaded from YAML config files.")
```

    Policy Summary
    ══════════════════════════════════════════════════════════════════
    Category      | Policy             | Key Parameter
    ─────────────|────────────────────|───────────────────────────────
    Individual    | StayHome           | compliance=0.85
    Individual    | Shielding          | min_age=70, compliance=0.85
    Interaction   | SocialDistancing   | school β×0.5
    Interaction   | MaskWearing        | β×0.5, prob=0.8
    ─────────────|────────────────────|───────────────────────────────

    In full JUNE simulations, policies are loaded from YAML config files.
