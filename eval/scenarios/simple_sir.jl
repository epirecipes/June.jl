# ============================================================================
# Simple SIR scenario — Julia side
#
# This file defines the SIR epidemic scenario parameters for the Julia runner.
# The actual simulation logic is in JuneCompare.run_julia_sir().
#
# Usage (standalone test):
#   julia --project=. -e '
#       include("eval/JuneCompare.jl")
#       using .JuneCompare
#       traj = run_julia_sir(42; n_people=200, n_steps=50)
#       println("Final S=$(last(traj.values["susceptible"])) ",
#               "I=$(last(traj.values["infected"])) ",
#               "R=$(last(traj.values["recovered"]))")
#   '
# ============================================================================

# Default scenario parameters
const SIR_DEFAULTS = Dict(
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
    describe_scenario()

Print a human-readable description of the Simple SIR scenario.
"""
function describe_scenario()
    println("Simple SIR Epidemic Scenario")
    println("────────────────────────────")
    println("  Population:           $(SIR_DEFAULTS[:n_people]) people")
    println("  Initial infected:     $(SIR_DEFAULTS[:n_initial_infected])")
    println("  Steps:                $(SIR_DEFAULTS[:n_steps])")
    println("  TransmissionGamma:")
    println("    max_infectiousness: $(SIR_DEFAULTS[:beta])")
    println("    shape:              $(SIR_DEFAULTS[:gamma_shape])")
    println("    rate:               $(SIR_DEFAULTS[:gamma_rate])")
    println("    shift:              $(SIR_DEFAULTS[:gamma_shift])")
    println("  Recovery:             $(SIR_DEFAULTS[:recovery_days]) days")
    println()
    println("Groups:")
    println("  - Households of 4 people")
    println("  - 1 School (ages ≤ 18)")
    println("  - 1 Company (ages > 18)")
    println()
    println("Algorithm:")
    println("  Each step:")
    println("    1. For each group, each infected person transmits to")
    println("       susceptible co-members with probability from TransmissionGamma")
    println("       evaluated at their days-since-infection")
    println("    2. Infected people with days ≥ recovery_days recover")
    println("  Tracked: susceptible, infected, recovered counts")
end
