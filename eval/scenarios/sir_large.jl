# ============================================================================
# SIR Large scenario — Julia side
#
# Same as Simple SIR but with 2000 people for scaling/performance testing.
# 2 schools and 2 companies.
#
# Usage (standalone test):
#   julia --project=. -e '
#       include("eval/JuneCompare.jl")
#       using .JuneCompare
#       traj = run_julia(SIRLarge(), 42; n_steps=100)
#       println("Final S=$(last(traj.values["susceptible"])) ",
#               "I=$(last(traj.values["infected"])) ",
#               "R=$(last(traj.values["recovered"]))")
#   '
# ============================================================================

const SIR_LARGE_DEFAULTS = Dict(
    :n_people            => 2000,
    :n_steps             => 100,
    :n_initial_infected  => 25,
    :beta                => 0.3,
    :gamma_shape         => 1.56,
    :gamma_rate          => 0.53,
    :gamma_shift         => -2.12,
    :recovery_days       => 14,
)

"""
    describe_sir_large()

Print a human-readable description of the SIR Large scenario.
"""
function describe_sir_large()
    println("SIR Large Epidemic Scenario")
    println("───────────────────────────")
    println("  Population:           $(SIR_LARGE_DEFAULTS[:n_people]) people")
    println("  Initial infected:     $(SIR_LARGE_DEFAULTS[:n_initial_infected])")
    println("  Steps:                $(SIR_LARGE_DEFAULTS[:n_steps])")
    println("  TransmissionGamma:")
    println("    max_infectiousness: $(SIR_LARGE_DEFAULTS[:beta])")
    println("    shape:              $(SIR_LARGE_DEFAULTS[:gamma_shape])")
    println("    rate:               $(SIR_LARGE_DEFAULTS[:gamma_rate])")
    println("    shift:              $(SIR_LARGE_DEFAULTS[:gamma_shift])")
    println("  Recovery:             $(SIR_LARGE_DEFAULTS[:recovery_days]) days")
    println()
    println("Groups:")
    println("  - Households of 4 people")
    println("  - 2 Schools (ages ≤ 18, split by even/odd index)")
    println("  - 2 Companies (ages > 18, split by even/odd index)")
    println()
    println("Algorithm:")
    println("  Same as Simple SIR but 10× population for performance testing.")
    println("  Tracked: susceptible, infected, recovered counts")
end
