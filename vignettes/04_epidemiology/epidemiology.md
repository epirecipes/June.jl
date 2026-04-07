# Epidemiology in June.jl


- [Disease Modelling](#disease-modelling)
  - [Transmission Profiles](#transmission-profiles)
  - [Peak Infectiousness](#peak-infectiousness)
  - [Symptom Tags](#symptom-tags)
  - [Symptoms and Health Index](#symptoms-and-health-index)
  - [Creating an Infection](#creating-an-infection)
  - [Immunity and Susceptibility](#immunity-and-susceptibility)
  - [Effective Multiplier](#effective-multiplier)

# Disease Modelling

June.jl models disease transmission using configurable parameters for:

- **Transmission**: How infectiousness varies over time (Gamma, XNExp,
  or Constant profiles)
- **Symptoms**: Disease progression through stages (exposed → mild →
  severe → hospitalised → ICU → recovery/death)
- **Infection**: Combines transmission and symptoms into a single object
- **Immunity**: Tracks susceptibility changes from natural infection or
  vaccination

## Transmission Profiles

The `TransmissionGamma` profile models how the probability of
transmission varies over time since infection, using a Gamma
distribution.

``` julia
using June

tg = TransmissionGamma(0.3, 1.56, 0.53, -2.12)
println("Parameters: max_infectiousness=0.3, shape=1.56, rate=0.53, shift=-2.12")
println()

# Tabulate the transmission curve
println("Day  | Probability | Profile")
println("─────|─────────────|────────────────────────────────────────")
for day in 0:20
    update_infection_probability!(tg, Float64(day))
    bar_len = round(Int, tg.probability * 200)
    bar = repeat("█", bar_len)
    println(lpad(day, 4), " | ", rpad(round(tg.probability, digits=6), 11), " | ", bar)
end
```

    Parameters: max_infectiousness=0.3, shape=1.56, rate=0.53, shift=-2.12

    Day  | Probability | Profile
    ─────|─────────────|────────────────────────────────────────
       0 | 0.25218     | ██████████████████████████████████████████████████
       1 | 0.184295    | █████████████████████████████████████
       2 | 0.126751    | █████████████████████████
       3 | 0.084261    | █████████████████
       4 | 0.054807    | ███████████
       5 | 0.035113    | ███████
       6 | 0.022246    | ████
       7 | 0.013974    | ███
       8 | 0.008719    | ██
       9 | 0.00541     | █
      10 | 0.003342    | █
      11 | 0.002056    | 
      12 | 0.001261    | 
      13 | 0.000771    | 
      14 | 0.000471    | 
      15 | 0.000286    | 
      16 | 0.000174    | 
      17 | 0.000106    | 
      18 | 6.4e-5      | 
      19 | 3.9e-5      | 
      20 | 2.3e-5      | 

## Peak Infectiousness

``` julia
# Find the peak by scanning at fine resolution
peak_time = 0.0
peak_prob = 0.0
for t in 0.0:0.01:20.0
    update_infection_probability!(tg, t)
    if tg.probability > peak_prob
        peak_prob = tg.probability
        peak_time = t
    end
end
println("Peak infectiousness: $(round(peak_prob, digits=6)) at day $(round(peak_time, digits=2))")
```

    Peak infectiousness: 0.25218 at day 0.0

## Symptom Tags

The disease progression follows a trajectory through symptom stages,
represented by the `SymptomTag` enum.

``` julia
println("Symptom stages (severity order):")
println("─" ^ 35)
for tag in instances(SymptomTag)
    println("  $(rpad(tag, 18)) = $(symptom_value(tag))")
end
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

## Symptoms and Health Index

A `Symptoms` object is initialized with a `health_index` vector —
cumulative probabilities that determine the maximum severity a person
can reach.

``` julia
# health_index: cumulative probabilities for [asymptomatic, mild, severe, hospitalised, ICU, dead]
health_index = [0.2, 0.5, 0.7, 0.85, 0.95, 1.0]
sym = Symptoms(health_index)
println("Initial symptom tag: $(sym.tag)")
println("Maximum severity tag: $(sym.max_tag)")
println("Max severity value: $(sym.max_severity)")
```

    Initial symptom tag: exposed
    Maximum severity tag: mild
    Max severity value: 0.49842911669354806

``` julia
# Different health indices model different risk profiles
young_healthy = [0.6, 0.9, 0.97, 0.99, 0.999, 1.0]
elderly_comorbid = [0.05, 0.15, 0.35, 0.55, 0.75, 1.0]

sym_young = Symptoms(young_healthy)
sym_old = Symptoms(elderly_comorbid)
println("Young healthy max severity: $(sym_young.max_tag)")
println("Elderly with comorbidity max severity: $(sym_old.max_tag)")
```

    Young healthy max severity: asymptomatic
    Elderly with comorbidity max severity: severe

## Creating an Infection

An `Infection` combines a transmission profile with symptoms and a start
time.

``` julia
tg2 = TransmissionGamma(0.3, 1.56, 0.53, -2.12)
sym2 = Symptoms([0.2, 0.5, 0.7, 0.85, 0.95, 1.0])
inf = Infection(tg2, sym2, 0.0)
println("Infection created at time 0.0")
println("  Transmission type: $(typeof(inf.transmission))")
println("  Current symptom tag: $(inf.symptoms.tag)")
println("  Infection probability: $(inf.transmission.probability)")
```

    Infection created at time 0.0
      Transmission type: June.TransmissionGamma
      Current symptom tag: exposed
      Infection probability: 0.0

## Immunity and Susceptibility

The `Immunity` type tracks a person’s susceptibility to each pathogen
(indexed by infection ID).

``` julia
imm = Immunity()
println("Default susceptibility to infection 0: $(get_susceptibility(imm, 0))")
println("Default susceptibility to infection 1: $(get_susceptibility(imm, 1))")

# Simulate vaccination reducing susceptibility
imm.susceptibility_dict[0] = 0.48
println()
println("After vaccination (sterilisation efficacy 52%):")
println("  Susceptibility to infection 0: $(get_susceptibility(imm, 0))")
println("  Susceptibility to infection 1: $(get_susceptibility(imm, 1))  (unchanged)")
```

    Default susceptibility to infection 0: 1.0
    Default susceptibility to infection 1: 1.0

    After vaccination (sterilisation efficacy 52%):
      Susceptibility to infection 0: 0.48
      Susceptibility to infection 1: 1.0  (unchanged)

## Effective Multiplier

The effective multiplier modifies how severely an infection manifests
(e.g., after vaccination).

``` julia
println("Default effective multiplier: $(get_effective_multiplier(imm, 0))")
imm.effective_multiplier_dict[0] = 0.3
println("After vaccination: $(get_effective_multiplier(imm, 0))")
```

    Default effective multiplier: 1.0
    After vaccination: 0.3
