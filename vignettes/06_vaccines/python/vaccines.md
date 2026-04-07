# Immunity and Vaccination in JUNE (Python)


- [Immunity and Vaccination](#immunity-and-vaccination)
  - [Setup](#setup)
  - [The Immunity Object](#the-immunity-object)
  - [Vaccination: Dose 1](#vaccination-dose-1)
  - [Vaccination: Dose 2](#vaccination-dose-2)
  - [Symptomatic Efficacy](#symptomatic-efficacy)
  - [Multi-Pathogen Immunity](#multi-pathogen-immunity)
  - [Vaccination Summary Table](#vaccination-summary-table)

# Immunity and Vaccination

JUNE models immunity through two mechanisms:

- **Susceptibility**: Probability of becoming infected upon exposure
  (reduced by vaccination)
- **Effective multiplier**: Modifies disease severity if infected
  (reduced by vaccination)

## Setup

``` python
import sys, types
fake_turtle = types.ModuleType('turtle')
fake_turtle.home = lambda: None
sys.modules['turtle'] = fake_turtle
```

## The Immunity Object

Every `Person` has an `Immunity` object. By default, everyone is fully
susceptible.

``` python
from june.epidemiology.infection import Immunity

imm = Immunity()
print("Default state:")
print(f"  Susceptibility to infection 0: {imm.get_susceptibility(0)}")
print(f"  Effective multiplier for infection 0: {imm.get_effective_multiplier(0)}")
```

    No --data argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/June.jl/vignettes/06_vaccines/python/data
    No --configs argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/JUNE/june/configs

    Default state:
      Susceptibility to infection 0: 1.0
      Effective multiplier for infection 0: 1.0

## Vaccination: Dose 1

After dose 1, sterilisation efficacy of 52% reduces susceptibility.

``` python
from june.demography import Person

p = Person.from_attributes(sex='m', age=70)
print("Before vaccination:")
print(f"  Susceptibility = {p.immunity.get_susceptibility(0)}")

dose1_sterilisation = 0.52
p.immunity.susceptibility_dict[0] = 1.0 - dose1_sterilisation
print()
print(f"After dose 1 (sterilisation efficacy = {dose1_sterilisation}):")
print(f"  Susceptibility = {p.immunity.get_susceptibility(0)}")
```

    Before vaccination:
      Susceptibility = 1.0

    After dose 1 (sterilisation efficacy = 0.52):
      Susceptibility = 0.48

## Vaccination: Dose 2

``` python
dose2_sterilisation = 0.95
p.immunity.susceptibility_dict[0] = 1.0 - dose2_sterilisation
print(f"After dose 2 (sterilisation efficacy = {dose2_sterilisation}):")
print(f"  Susceptibility = {p.immunity.get_susceptibility(0)}")
```

    After dose 2 (sterilisation efficacy = 0.95):
      Susceptibility = 0.050000000000000044

## Symptomatic Efficacy

Vaccination also reduces disease severity through the effective
multiplier.

``` python
print("Before vaccination:")
print(f"  Effective multiplier = {p.immunity.get_effective_multiplier(0)}")

dose1_symptomatic = 0.60
p.immunity.effective_multiplier_dict[0] = 1.0 - dose1_symptomatic
print()
print(f"After dose 1 (symptomatic efficacy = {dose1_symptomatic}):")
print(f"  Effective multiplier = {p.immunity.get_effective_multiplier(0)}")

dose2_symptomatic = 0.90
p.immunity.effective_multiplier_dict[0] = 1.0 - dose2_symptomatic
print()
print(f"After dose 2 (symptomatic efficacy = {dose2_symptomatic}):")
print(f"  Effective multiplier = {p.immunity.get_effective_multiplier(0)}")
```

    Before vaccination:
      Effective multiplier = 1.0

    After dose 1 (symptomatic efficacy = 0.6):
      Effective multiplier = 0.4

    After dose 2 (symptomatic efficacy = 0.9):
      Effective multiplier = 0.09999999999999998

## Multi-Pathogen Immunity

Immunity is tracked per infection ID, allowing multi-pathogen scenarios.

``` python
imm2 = Immunity()
print("Two-pathogen scenario:")
print(f"  Infection 0 susceptibility: {imm2.get_susceptibility(0)}")
print(f"  Infection 1 susceptibility: {imm2.get_susceptibility(1)}")

imm2.susceptibility_dict[0] = 0.05
print()
print("After vaccination against pathogen 0:")
print(f"  Infection 0 susceptibility: {imm2.get_susceptibility(0)}")
print(f"  Infection 1 susceptibility: {imm2.get_susceptibility(1)}  (unchanged)")
```

    Two-pathogen scenario:
      Infection 0 susceptibility: 1.0
      Infection 1 susceptibility: 1.0

    After vaccination against pathogen 0:
      Infection 0 susceptibility: 0.05
      Infection 1 susceptibility: 1.0  (unchanged)

## Vaccination Summary Table

``` python
print("Vaccination Impact Summary")
print("═" * 58)
print(f"{'Dose':>4} | {'Sterilisation':>13} | {'Susceptibility':>14} | {'Symptomatic':>11} | {'Eff. Mult.':>10}")
print("─" * 5 + "|" + "─" * 15 + "|" + "─" * 16 + "|" + "─" * 13 + "|" + "─" * 11)
for d, se, sye in [(0, 0.0, 0.0), (1, 0.52, 0.60), (2, 0.95, 0.90)]:
    susc = round(1.0 - se, 2)
    em = round(1.0 - sye, 2)
    print(f"  {d}  | {se:>13} | {susc:>14} | {sye:>11} | {em:>10}")
```

    Vaccination Impact Summary
    ══════════════════════════════════════════════════════════
    Dose | Sterilisation | Susceptibility | Symptomatic | Eff. Mult.
    ─────|───────────────|────────────────|─────────────|───────────
      0  |           0.0 |            1.0 |         0.0 |        1.0
      1  |          0.52 |           0.48 |         0.6 |        0.4
      2  |          0.95 |           0.05 |         0.9 |        0.1
