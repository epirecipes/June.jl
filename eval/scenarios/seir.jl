# ============================================================================
# SEIR scenario — Julia side
#
# SIR with exposed/latent period. People go S→E→I→R.
# Exposed people are NOT infectious. After exposed_days they become infected.
#
# Usage (standalone test):
#   julia --project=. -e '
#       include("eval/JuneCompare.jl")
#       using .JuneCompare
#       traj = run_julia(SEIR(), 42; n_steps=50)
#       println("Final S=$(last(traj.values["susceptible"])) ",
#               "E=$(last(traj.values["exposed"])) ",
#               "I=$(last(traj.values["infected"])) ",
#               "R=$(last(traj.values["recovered"]))")
#   '
# ============================================================================

const SEIR_DEFAULTS = Dict(
    :n_people            => 200,
    :n_steps             => 50,
    :n_initial_infected  => 5,
    :beta                => 0.3,
    :gamma_shape         => 1.56,
    :gamma_rate          => 0.53,
    :gamma_shift         => -2.12,
    :recovery_days       => 14,
    :exposed_days        => 3,
)

"""
    describe_seir()

Print a human-readable description of the SEIR scenario.
"""
function describe_seir()
    println("SEIR Epidemic Scenario")
    println("──────────────────────")
    println("  Population:           $(SEIR_DEFAULTS[:n_people]) people")
    println("  Initial infected:     $(SEIR_DEFAULTS[:n_initial_infected])")
    println("  Steps:                $(SEIR_DEFAULTS[:n_steps])")
    println("  Exposed period:       $(SEIR_DEFAULTS[:exposed_days]) days")
    println("  TransmissionGamma:")
    println("    max_infectiousness: $(SEIR_DEFAULTS[:beta])")
    println("    shape:              $(SEIR_DEFAULTS[:gamma_shape])")
    println("    rate:               $(SEIR_DEFAULTS[:gamma_rate])")
    println("    shift:              $(SEIR_DEFAULTS[:gamma_shift])")
    println("  Recovery:             $(SEIR_DEFAULTS[:recovery_days]) days")
    println()
    println("Groups:")
    println("  - Households of 4 people")
    println("  - 1 School (ages ≤ 18)")
    println("  - 1 Company (ages > 18)")
    println()
    println("Algorithm:")
    println("  Each step:")
    println("    1. Infected transmit to susceptible → become EXPOSED")
    println("    2. Exposed with days ≥ exposed_days → become infected")
    println("    3. Infected with days ≥ recovery_days → recover")
    println("  Tracked: susceptible, exposed, infected, recovered counts")
end
