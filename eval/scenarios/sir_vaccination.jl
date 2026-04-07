# ============================================================================
# SIR Vaccination scenario — Julia side
#
# SIR where 30% of the population starts vaccinated (susceptibility=0.3).
# Uses June.jl's Immunity type for reduced susceptibility.
# Tracks vaccinated people who get infected separately.
#
# Usage (standalone test):
#   julia --project=. -e '
#       include("eval/JuneCompare.jl")
#       using .JuneCompare
#       traj = run_julia(SIRVaccination(), 42; n_steps=50)
#       println("Final S=$(last(traj.values["susceptible"])) ",
#               "I=$(last(traj.values["infected"])) ",
#               "R=$(last(traj.values["recovered"])) ",
#               "VI=$(last(traj.values["vaccinated_infected"]))")
#   '
# ============================================================================

const SIR_VACCINATION_DEFAULTS = Dict(
    :n_people                    => 200,
    :n_steps                     => 50,
    :n_initial_infected          => 5,
    :beta                        => 0.3,
    :gamma_shape                 => 1.56,
    :gamma_rate                  => 0.53,
    :gamma_shift                 => -2.12,
    :recovery_days               => 14,
    :vaccination_fraction        => 0.3,
    :vaccination_susceptibility  => 0.3,
)

"""
    describe_sir_vaccination()

Print a human-readable description of the SIR Vaccination scenario.
"""
function describe_sir_vaccination()
    println("SIR Vaccination Epidemic Scenario")
    println("─────────────────────────────────")
    println("  Population:           $(SIR_VACCINATION_DEFAULTS[:n_people]) people")
    println("  Initial infected:     $(SIR_VACCINATION_DEFAULTS[:n_initial_infected])")
    println("  Steps:                $(SIR_VACCINATION_DEFAULTS[:n_steps])")
    println("  Vaccination fraction: $(SIR_VACCINATION_DEFAULTS[:vaccination_fraction])")
    println("  Vaccinated suscept.:  $(SIR_VACCINATION_DEFAULTS[:vaccination_susceptibility])")
    println("  TransmissionGamma:")
    println("    max_infectiousness: $(SIR_VACCINATION_DEFAULTS[:beta])")
    println("    shape:              $(SIR_VACCINATION_DEFAULTS[:gamma_shape])")
    println("    rate:               $(SIR_VACCINATION_DEFAULTS[:gamma_rate])")
    println("    shift:              $(SIR_VACCINATION_DEFAULTS[:gamma_shift])")
    println("  Recovery:             $(SIR_VACCINATION_DEFAULTS[:recovery_days]) days")
    println()
    println("Groups:")
    println("  - Households of 4 people")
    println("  - 1 School (ages ≤ 18)")
    println("  - 1 Company (ages > 18)")
    println()
    println("Algorithm:")
    println("  Same as Simple SIR but 30% start vaccinated.")
    println("  Vaccinated have susceptibility=0.3 (via Immunity type).")
    println("  Tracked: susceptible, infected, recovered, vaccinated_infected")
end
