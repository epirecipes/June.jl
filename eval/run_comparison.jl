#!/usr/bin/env julia
#
# Run stochastic trajectory comparisons between June.jl (Julia)
# and the reference Python JUNE implementation.
#
# Usage:
#   cd June.jl
#   julia --project=. eval/run_comparison.jl [mode] [model] [n_reps] [n_steps]
#
# Modes:
#   calibrated  (default) 4-batch null-calibrated comparison
#   simple                Single-batch comparison with threshold metrics
#   julia-only            Quick smoke test (Julia only, no Python)
#   benchmark             Speed + memory benchmark (no statistical comparison)
#
# Models:
#   all (default), simple_sir, household_sir, seir, age_structured, vaccination, large
#
# Examples:
#   julia --project=. eval/run_comparison.jl                           # calibrated, all models, 50/batch
#   julia --project=. eval/run_comparison.jl calibrated all 50 50      # same, explicit
#   julia --project=. eval/run_comparison.jl calibrated seir 30 50     # SEIR only, 30/batch
#   julia --project=. eval/run_comparison.jl benchmark all 10          # benchmark all, 10 reps
#   julia --project=. eval/run_comparison.jl julia-only all 3 30       # smoke test all models
#

using June
using Printf

include(joinpath(@__DIR__, "JuneCompare.jl"))
using .JuneCompare

function resolve_scenarios(model_arg::String)
    if model_arg == "all"
        return collect(values(MODELS))
    elseif haskey(MODELS, model_arg)
        return [MODELS[model_arg]]
    else
        error("Unknown model: $model_arg. Available: all, $(join(keys(MODELS), ", "))")
    end
end

function julia_only_smoke_test(scenarios::Vector{<:JuneCompare.AbstractScenario},
                               n_reps::Int, n_steps_override::Union{Nothing,Int})
    println("═══════════════════════════════════════════════════")
    println("  Julia-only smoke test (no Python comparison)")
    println("  $n_reps reps  │  Scenarios: $(length(scenarios))")
    println("═══════════════════════════════════════════════════\n")

    seeds = collect(1:n_reps)

    for scenario in scenarios
        ns = n_steps_override !== nothing ? n_steps_override : JuneCompare.default_n_steps(scenario)
        name = JuneCompare.scenario_name(scenario)
        vars = JuneCompare.tracked_vars(scenario)

        println("  ▶ $(name) ($n_reps reps × $ns steps)")
        t = @elapsed trajs = JuneCompare.run_julia_trajectories(scenario, seeds; n_steps=ns)
        @printf("    ✓ Completed in %.2fs (%.3fs/rep)\n", t, t/n_reps)

        for traj in trajs
            finals = Dict(g => last(v) for (g, v) in traj.values)
            parts = join(["$(uppercase(g[1:1]))=$(finals[g])" for g in vars if haskey(finals, g)], "  ")
            @printf("    seed %3d: %s\n", traj.seed, parts)
        end
        println()
    end
end

function run_calibrated(scenarios::Vector{<:JuneCompare.AbstractScenario},
                        n_per_batch::Int, n_steps_override::Union{Nothing,Int})
    outdir = joinpath(@__DIR__, "results")
    mkpath(outdir)

    for scenario in scenarios
        ns = n_steps_override !== nothing ? n_steps_override : JuneCompare.default_n_steps(scenario)
        name = JuneCompare.scenario_name(scenario)

        try
            report = compare_model_calibrated(scenario; n_per_batch=n_per_batch, n_steps=ns)
            print_calibrated_report(report)

            safe_name = replace(lowercase(name), r"[^a-z0-9]+" => "_")
            csv_path = joinpath(outdir, "$(safe_name)_calibrated.csv")
            save_calibrated_csv(report, csv_path)
        catch e
            println("\n  ❌ Error in $name: $e")
            println("     $(sprint(showerror, e))")
            for (exc, bt) in Base.catch_stack()
                showerror(stderr, exc, bt)
                println(stderr)
            end
        end
    end
end

function run_simple(scenarios::Vector{<:JuneCompare.AbstractScenario},
                    n_reps::Int, n_steps_override::Union{Nothing,Int})
    outdir = joinpath(@__DIR__, "results")
    mkpath(outdir)

    for scenario in scenarios
        ns = n_steps_override !== nothing ? n_steps_override : JuneCompare.default_n_steps(scenario)
        name = JuneCompare.scenario_name(scenario)

        try
            report = compare_model(scenario; n_reps=n_reps, n_steps=ns)
            print_report(report)

            safe_name = replace(lowercase(name), r"[^a-z0-9]+" => "_")
            csv_path = joinpath(outdir, "$(safe_name).csv")
            save_csv(report, csv_path)
        catch e
            println("\n  ❌ Error in $name: $e")
            println("     $(sprint(showerror, e))")
        end
    end
end

function run_benchmark_mode(scenarios::Vector{<:JuneCompare.AbstractScenario},
                            n_reps::Int, n_steps_override::Union{Nothing,Int})
    outdir = joinpath(@__DIR__, "results")
    mkpath(outdir)

    println("═══════════════════════════════════════════════════")
    println("  Speed + Memory Benchmark")
    println("  $n_reps reps  │  Scenarios: $(length(scenarios))")
    println("═══════════════════════════════════════════════════\n")

    results = JuneCompare.run_all_benchmarks(scenarios; n_reps=n_reps, n_steps_override=n_steps_override)
    JuneCompare.print_benchmark_report(results)

    csv_path = joinpath(outdir, "benchmark.csv")
    JuneCompare.save_benchmark_csv(results, csv_path)
end

function main()
    mode     = length(ARGS) >= 1 ? lowercase(ARGS[1]) : "calibrated"
    model    = length(ARGS) >= 2 ? lowercase(ARGS[2]) : "all"
    n_reps   = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 50
    n_steps_arg = length(ARGS) >= 4 ? parse(Int, ARGS[4]) : nothing

    scenarios = resolve_scenarios(model)
    model_names = join([JuneCompare.scenario_name(s) for s in scenarios], ", ")

    println("═══════════════════════════════════════════════════")
    println("  June.jl vs Python JUNE — Evaluation Framework")
    println("  Mode: $mode  │  Reps: $n_reps")
    println("  Models: $model_names")
    if n_steps_arg !== nothing
        println("  Steps override: $n_steps_arg")
    end
    println("═══════════════════════════════════════════════════\n")

    if mode == "julia-only"
        julia_only_smoke_test(scenarios, n_reps, n_steps_arg)
    elseif mode == "calibrated"
        run_calibrated(scenarios, n_reps, n_steps_arg)
    elseif mode == "simple"
        run_simple(scenarios, n_reps, n_steps_arg)
    elseif mode == "benchmark"
        run_benchmark_mode(scenarios, n_reps, n_steps_arg)
    else
        error("Unknown mode: $mode. Use 'calibrated', 'simple', 'julia-only', or 'benchmark'")
    end
end

main()
