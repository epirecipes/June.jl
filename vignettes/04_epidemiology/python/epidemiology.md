# Epidemiology in JUNE (Python)


- [Disease Modelling](#disease-modelling)
  - [Setup](#setup)
  - [Transmission Profiles](#transmission-profiles)
  - [Peak Infectiousness](#peak-infectiousness)
  - [Symptom Tags](#symptom-tags)
  - [Immunity and Susceptibility](#immunity-and-susceptibility)
  - [Effective Multiplier](#effective-multiplier)

# Disease Modelling

JUNE models disease transmission using configurable parameters for:

- **Transmission**: How infectiousness varies over time (Gamma, XNExp,
  or Constant profiles)
- **Symptoms**: Disease progression through stages
- **Immunity**: Tracks susceptibility changes from natural infection or
  vaccination

## Setup

``` python
import sys, types
fake_turtle = types.ModuleType('turtle')
fake_turtle.home = lambda: None
sys.modules['turtle'] = fake_turtle
```

## Transmission Profiles

The `TransmissionGamma` profile models how the probability of
transmission varies over time since infection.

``` python
from june.epidemiology.infection.transmission import TransmissionGamma

tg = TransmissionGamma(max_infectiousness=0.3, shape=1.56, rate=0.53, shift=-2.12)
print("Parameters: max_infectiousness=0.3, shape=1.56, rate=0.53, shift=-2.12")
print()
print(f"{'Day':>4} | {'Probability':<12} | Profile")
print("─" * 5 + "|" + "─" * 14 + "|" + "─" * 40)
for day in range(21):
    tg.update_infection_probability(float(day))
    bar_len = int(tg.probability * 200)
    bar = "█" * bar_len
    print(f"{day:4d} | {tg.probability:<12.6f} | {bar}")
```

    No --data argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/June.jl/vignettes/04_epidemiology/python/data
    No --configs argument given - defaulting to:
    /Users/sdwfrost/Projects/june/code/JUNE/june/configs

    Parameters: max_infectiousness=0.3, shape=1.56, rate=0.53, shift=-2.12

     Day | Probability  | Profile
    ─────|──────────────|────────────────────────────────────────
       0 | 0.062023     | ████████████
       1 | 0.045327     | █████████
       2 | 0.031174     | ██████
       3 | 0.020724     | ████
       4 | 0.013480     | ██
       5 | 0.008636     | █
       6 | 0.005471     | █
       7 | 0.003437     | 
       8 | 0.002144     | 
       9 | 0.001331     | 
      10 | 0.000822     | 
      11 | 0.000506     | 
      12 | 0.000310     | 
      13 | 0.000190     | 
      14 | 0.000116     | 
      15 | 0.000070     | 
      16 | 0.000043     | 
      17 | 0.000026     | 
      18 | 0.000016     | 
      19 | 0.000010     | 
      20 | 0.000006     | 

## Peak Infectiousness

``` python
peak_time = 0.0
peak_prob = 0.0
for t_int in range(2001):
    t = t_int * 0.01
    tg.update_infection_probability(t)
    if tg.probability > peak_prob:
        peak_prob = tg.probability
        peak_time = t
print(f"Peak infectiousness: {peak_prob:.6f} at day {peak_time:.2f}")
```

    Peak infectiousness: 0.062023 at day 0.00

## Symptom Tags

The disease progression follows a trajectory through symptom stages,
represented by the `SymptomTag` enum.

``` python
from june.epidemiology.infection.symptom_tag import SymptomTag

print("Symptom stages (severity order):")
print("─" * 35)
for tag in SymptomTag:
    print(f"  {tag.name:<18} = {tag.value}")
```

    Symptom stages (severity order):
    ───────────────────────────────────
      recovered          = -3
      healthy            = -2
      exposed            = -1
      asymptomatic       = 0
      mild               = 1
      severe             = 2
      hospitalised       = 3
      intensive_care     = 4
      dead_home          = 5
      dead_hospital      = 6
      dead_icu           = 7

## Immunity and Susceptibility

The `Immunity` type tracks a person’s susceptibility to each pathogen.

``` python
from june.epidemiology.infection import Immunity

imm = Immunity()
print(f"Default susceptibility to infection 0: {imm.get_susceptibility(0)}")
print(f"Default susceptibility to infection 1: {imm.get_susceptibility(1)}")

imm.susceptibility_dict[0] = 0.48
print()
print("After vaccination (sterilisation efficacy 52%):")
print(f"  Susceptibility to infection 0: {imm.get_susceptibility(0)}")
print(f"  Susceptibility to infection 1: {imm.get_susceptibility(1)}  (unchanged)")
```

    Default susceptibility to infection 0: 1.0
    Default susceptibility to infection 1: 1.0

    After vaccination (sterilisation efficacy 52%):
      Susceptibility to infection 0: 0.48
      Susceptibility to infection 1: 1.0  (unchanged)

## Effective Multiplier

The effective multiplier modifies how severely an infection manifests.

``` python
print(f"Default effective multiplier: {imm.get_effective_multiplier(0)}")
imm.effective_multiplier_dict[0] = 0.3
print(f"After vaccination: {imm.get_effective_multiplier(0)}")
```

    Default effective multiplier: 1.0
    After vaccination: 0.3
