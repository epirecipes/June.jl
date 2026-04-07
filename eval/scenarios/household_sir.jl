# ============================================================================
# Household SIR scenario — Julia side
#
# SIR with household-only transmission (no school/company).
# Tests small-group dynamics with higher beta.
#
# Usage (standalone test):
#   julia --project=. -e '
#       include("eval/JuneCompare.jl")
#       using .JuneCompare
#       traj = run_julia(HouseholdSIR(), 42; n_steps=50)
#       println("Final S=$(last(traj.values["susceptible"])) ",
#               "I=$(last(traj.values["infected"])) ",
#               "R=$(last(traj.values["recovered"]))")
#   '
# ============================================================================

const HOUSEHOLD_SIR_DEFAULTS = Dict(
    :n_people            => 200,
    :n_steps             => 50,
    :n_initial_infected  => 5,
    :beta                => 0.5,  # higher beta since fewer contacts
    :gamma_shape         => 1.56,
    :gamma_rate          => 0.53,
    :gamma_shift         => -2.12,
    :recovery_days       => 14,
)

"""
    describe_household_sir()

Print a human-readable description of the Household SIR scenario.
"""
function describe_household_sir()
    println("Household SIR Epidemic Scenario")
    println("───────────────────────────────")
    println("  Population:           $(HOUSEHOLD_SIR_DEFAULTS[:n_people]) people")
    println("  Initial infected:     $(HOUSEHOLD_SIR_DEFAULTS[:n_initial_infected])")
    println("  Steps:                $(HOUSEHOLD_SIR_DEFAULTS[:n_steps])")
    println("  TransmissionGamma:")
    println("    max_infectiousness: $(HOUSEHOLD_SIR_DEFAULTS[:beta])")
    println("    shape:              $(HOUSEHOLD_SIR_DEFAULTS[:gamma_shape])")
    println("    rate:               $(HOUSEHOLD_SIR_DEFAULTS[:gamma_rate])")
    println("    shift:              $(HOUSEHOLD_SIR_DEFAULTS[:gamma_shift])")
    println("  Recovery:             $(HOUSEHOLD_SIR_DEFAULTS[:recovery_days]) days")
    println()
    println("Groups:")
    println("  - Households of 4 people ONLY (no school/company)")
    println()
    println("Algorithm:")
    println("  Same as Simple SIR but with household-only transmission.")
    println("  Higher beta compensates for fewer contact opportunities.")
    println("  Tracked: susceptible, infected, recovered counts")
end
