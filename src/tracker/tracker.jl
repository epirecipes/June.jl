# ============================================================================
# Tracker — accumulate contact matrices and population statistics
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

mutable struct Tracker
    age_bins::Vector{Int}
    contact_matrices::Dict{String, Matrix{Float64}}
    cum_time::Dict{String, Float64}
    cum_pop::Dict{String, Float64}
end

"""
    Tracker(; world=nothing, age_bins=collect(0:100))

Create a new tracker for recording group contact patterns.
"""
function Tracker(; world=nothing, age_bins::Vector{Int}=collect(0:100))
    contact_matrices = Dict{String, Matrix{Float64}}()
    cum_time  = Dict{String, Float64}()
    cum_pop   = Dict{String, Float64}()
    return Tracker(age_bins, contact_matrices, cum_time, cum_pop)
end

"""
    tracker_timestep!(tracker::Tracker, super_groups, timer::Timer)

Update contact matrices for each active super-group at this time-step.
"""
function tracker_timestep!(tracker::Tracker, super_groups, timer::Timer)
    n_bins = length(tracker.age_bins) - 1
    if n_bins < 1
        return
    end

    dt = timer.duration  # step length in days

    for sg in super_groups
        spec = sg.spec
        # Ensure matrix exists
        if !haskey(tracker.contact_matrices, spec)
            tracker.contact_matrices[spec] = zeros(n_bins, n_bins)
            tracker.cum_time[spec]  = 0.0
            tracker.cum_pop[spec]   = 0.0
        end

        cm = tracker.contact_matrices[spec]

        for grp in sg
            ppl = people(grp)
            n = length(ppl)
            n <= 1 && continue

            tracker.cum_time[spec] += dt
            tracker.cum_pop[spec]  += n * dt

            for p in ppl
                bin_i = _age_to_bin(p.age, tracker.age_bins)
                bin_i === nothing && continue
                for q in ppl
                    p.id == q.id && continue
                    bin_j = _age_to_bin(q.age, tracker.age_bins)
                    bin_j === nothing && continue
                    cm[bin_i, bin_j] += dt / max(n - 1, 1)
                end
            end
        end
    end
end

"""
    _age_to_bin(age, age_bins)

Return the 1-based bin index for `age`, or `nothing` if out of range.
"""
function _age_to_bin(age::Int, age_bins::Vector{Int})
    n = length(age_bins)
    for i in 1:(n - 1)
        if age >= age_bins[i] && age < age_bins[i + 1]
            return i
        end
    end
    # Include the last bin boundary
    if age == age_bins[end]
        return n - 1
    end
    return nothing
end

"""
    calc_average_contacts(tracker::Tracker)

Compute the mean number of contacts per person per day for each group spec.
Returns a `Dict{String, Float64}`.
"""
function calc_average_contacts(tracker::Tracker)
    result = Dict{String, Float64}()
    for (spec, cm) in tracker.contact_matrices
        total_contacts = sum(cm)
        pop_time = get(tracker.cum_pop, spec, 0.0)
        if pop_time > 0.0
            result[spec] = total_contacts / pop_time
        else
            result[spec] = 0.0
        end
    end
    return result
end

"""
    reset!(tracker::Tracker)

Clear all accumulated data.
"""
function reset!(tracker::Tracker)
    empty!(tracker.contact_matrices)
    empty!(tracker.cum_time)
    empty!(tracker.cum_pop)
end

function Base.show(io::IO, t::Tracker)
    n_specs = length(t.contact_matrices)
    print(io, "Tracker(specs=$n_specs, age_bins=$(length(t.age_bins)-1) bins)")
end
