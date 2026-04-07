# ============================================================================
# Age-Structured SIR scenario — Julia side
#
# SIR with age-dependent transmission probability.
# Transmission multiplier by susceptible person's age:
#   children (≤18): 1.5×, adults (19-64): 1.0×, elderly (65+): 0.8×
#
# Usage (standalone test):
#   julia --project=. -e '
#       include("eval/JuneCompare.jl")
#       using .JuneCompare
#       traj = run_julia(AgeStructuredSIR(), 42; n_steps=50)
#       println("Final S=$(last(traj.values["susceptible"])) ",
#               "I=$(last(traj.values["infected"])) ",
#               "R=$(last(traj.values["recovered"]))")
#   '
# ============================================================================

const AGE_STRUCTURED_SIR_DEFAULTS = Dict(
    :n_people            => 200,
    :n_steps             => 50,
    :n_initial_infected  => 5,
    :beta                => 0.3,
    :gamma_shape         => 1.56,
    :gamma_rate          => 0.53,
    :gamma_shift         => -2.12,
    :recovery_days       => 14,
)

"""
    describe_age_structured_sir()

Print a human-readable description of the Age-Structured SIR scenario.
"""
function describe_age_structured_sir()
    println("Age-Structured SIR Epidemic Scenario")
    println("────────────────────────────────────")
    println("  Population:           $(AGE_STRUCTURED_SIR_DEFAULTS[:n_people]) people")
    println("  Initial infected:     $(AGE_STRUCTURED_SIR_DEFAULTS[:n_initial_infected])")
    println("  Steps:                $(AGE_STRUCTURED_SIR_DEFAULTS[:n_steps])")
    println("  TransmissionGamma:")
    println("    max_infectiousness: $(AGE_STRUCTURED_SIR_DEFAULTS[:beta])")
    println("    shape:              $(AGE_STRUCTURED_SIR_DEFAULTS[:gamma_shape])")
    println("    rate:               $(AGE_STRUCTURED_SIR_DEFAULTS[:gamma_rate])")
    println("    shift:              $(AGE_STRUCTURED_SIR_DEFAULTS[:gamma_shift])")
    println("  Recovery:             $(AGE_STRUCTURED_SIR_DEFAULTS[:recovery_days]) days")
    println()
    println("Age multipliers (applied to susceptible person):")
    println("  - Children (≤18):  1.5×")
    println("  - Adults (19-64):  1.0×")
    println("  - Elderly (65+):   0.8×")
    println()
    println("Groups:")
    println("  - Households of 4 people")
    println("  - 1 School (ages ≤ 18)")
    println("  - 1 Company (ages > 18)")
    println()
    println("Algorithm:")
    println("  Same as Simple SIR but transmission probability is multiplied")
    println("  by age-dependent factor of the susceptible person.")
    println("  Tracked: susceptible, infected, recovered counts")
end
