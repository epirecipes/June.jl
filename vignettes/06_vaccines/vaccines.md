# Immunity and Vaccination in June.jl


- [Immunity and Vaccination](#immunity-and-vaccination)
  - [The Immunity Object](#the-immunity-object)
  - [Vaccination: Dose 1](#vaccination-dose-1)
  - [Vaccination: Dose 2](#vaccination-dose-2)
  - [Symptomatic Efficacy](#symptomatic-efficacy)
  - [Dose Object](#dose-object)
  - [Multi-Pathogen Immunity](#multi-pathogen-immunity)
  - [Vaccination Summary Table](#vaccination-summary-table)

# Immunity and Vaccination

June.jl models immunity through two mechanisms:

- **Susceptibility**: Probability of becoming infected upon exposure
  (reduced by vaccination)
- **Effective multiplier**: Modifies disease severity if infected
  (reduced by vaccination)

## The Immunity Object

Every `Person` has an `Immunity` object. By default, everyone is fully
susceptible.

``` julia
using June

imm = Immunity()
println("Default state:")
println("  Susceptibility to infection 0: $(get_susceptibility(imm, 0))")
println("  Effective multiplier for infection 0: $(get_effective_multiplier(imm, 0))")
```

    Default state:
      Susceptibility to infection 0: 1.0
      Effective multiplier for infection 0: 1.0

## Vaccination: Dose 1

After dose 1, sterilisation efficacy of 52% reduces susceptibility.

``` julia
p = Person(; sex='m', age=70)
p.immunity = Immunity()
println("Before vaccination:")
println("  Susceptibility = $(get_susceptibility(p.immunity, 0))")

# Dose 1: 52% sterilisation efficacy
dose1_sterilisation = 0.52
p.immunity.susceptibility_dict[0] = 1.0 - dose1_sterilisation
println()
println("After dose 1 (sterilisation efficacy = $(dose1_sterilisation)):")
println("  Susceptibility = $(get_susceptibility(p.immunity, 0))")
```

    Before vaccination:
      Susceptibility = 1.0

    After dose 1 (sterilisation efficacy = 0.52):
      Susceptibility = 0.48

## Vaccination: Dose 2

Dose 2 boosts protection with 95% sterilisation efficacy.

``` julia
dose2_sterilisation = 0.95
p.immunity.susceptibility_dict[0] = 1.0 - dose2_sterilisation
println("After dose 2 (sterilisation efficacy = $(dose2_sterilisation)):")
println("  Susceptibility = $(get_susceptibility(p.immunity, 0))")
```

    After dose 2 (sterilisation efficacy = 0.95):
      Susceptibility = 0.050000000000000044

## Symptomatic Efficacy

Vaccination also reduces disease severity through the effective
multiplier.

``` julia
println("Before vaccination:")
println("  Effective multiplier = $(get_effective_multiplier(p.immunity, 0))")

# Dose 1: 60% symptomatic efficacy
dose1_symptomatic = 0.60
p.immunity.effective_multiplier_dict[0] = 1.0 - dose1_symptomatic
println()
println("After dose 1 (symptomatic efficacy = $(dose1_symptomatic)):")
println("  Effective multiplier = $(get_effective_multiplier(p.immunity, 0))")

# Dose 2: 90% symptomatic efficacy
dose2_symptomatic = 0.90
p.immunity.effective_multiplier_dict[0] = 1.0 - dose2_symptomatic
println()
println("After dose 2 (symptomatic efficacy = $(dose2_symptomatic)):")
println("  Effective multiplier = $(get_effective_multiplier(p.immunity, 0))")
```

    Before vaccination:
      Effective multiplier = 1.0

    After dose 1 (symptomatic efficacy = 0.6):
      Effective multiplier = 0.4

    After dose 2 (symptomatic efficacy = 0.9):
      Effective multiplier = 0.09999999999999998

## Dose Object

The `Dose` type models time-varying efficacy with three phases:
building, effective, and waning.

``` julia
dose = Dose(;
    sterilisation_efficacy=Dict(0 => 0.52),
    symptomatic_efficacy=Dict(0 => 0.60),
    days_administered_to_effective=14.0,
    days_effective_to_waning=180.0,
    days_waning=90.0,
    waning_factor=0.5,
)
println("Dose configuration:")
println("  Sterilisation efficacy (infection 0): $(dose.sterilisation_efficacy[0])")
println("  Symptomatic efficacy (infection 0): $(dose.symptomatic_efficacy[0])")
println("  Days to effective: $(dose.days_administered_to_effective)")
println("  Days effective: $(dose.days_effective_to_waning)")
println("  Days waning: $(dose.days_waning)")
println("  Waning factor: $(dose.waning_factor)")
```

    Dose configuration:
      Sterilisation efficacy (infection 0): 0.52
      Symptomatic efficacy (infection 0): 0.6
      Days to effective: 14.0
      Days effective: 180.0
      Days waning: 90.0
      Waning factor: 0.5

## Multi-Pathogen Immunity

Immunity is tracked per infection ID, allowing multi-pathogen scenarios.

``` julia
imm2 = Immunity()
println("Two-pathogen scenario:")
println("  Infection 0 susceptibility: $(get_susceptibility(imm2, 0))")
println("  Infection 1 susceptibility: $(get_susceptibility(imm2, 1))")

# Vaccinate against pathogen 0 only
imm2.susceptibility_dict[0] = 0.05
println()
println("After vaccination against pathogen 0:")
println("  Infection 0 susceptibility: $(get_susceptibility(imm2, 0))")
println("  Infection 1 susceptibility: $(get_susceptibility(imm2, 1))  (unchanged)")
```

    Two-pathogen scenario:
      Infection 0 susceptibility: 1.0
      Infection 1 susceptibility: 1.0

    After vaccination against pathogen 0:
      Infection 0 susceptibility: 0.05
      Infection 1 susceptibility: 1.0  (unchanged)

## Vaccination Summary Table

``` julia
println("Vaccination Impact Summary")
println("══════════════════════════════════════════════════════════")
println("Dose | Sterilisation | Susceptibility | Symptomatic | Eff. Mult.")
println("─────|───────────────|────────────────|─────────────|──────────")
for (d, se, sye) in [(0, 0.0, 0.0), (1, 0.52, 0.60), (2, 0.95, 0.90)]
    susc = round(1.0 - se, digits=2)
    em = round(1.0 - sye, digits=2)
    println("  $(d)  |     $(rpad(se, 9))  |      $(rpad(susc, 9)) |    $(rpad(sye, 7))  |   $(em)")
end
```

    Vaccination Impact Summary
    ══════════════════════════════════════════════════════════
    Dose | Sterilisation | Susceptibility | Symptomatic | Eff. Mult.
    ─────|───────────────|────────────────|─────────────|──────────
      0  |     0.0        |      1.0       |    0.0      |   1.0
      1  |     0.52       |      0.48      |    0.6      |   0.4
      2  |     0.95       |      0.05      |    0.9      |   0.1
