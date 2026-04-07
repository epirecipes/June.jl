# ============================================================================
# Record — accumulate and persist simulation output
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

mutable struct Record
    record_path::String
    record_static_data::Bool
    infection_buffer::Vector{NamedTuple}
    hospital_admission_buffer::Vector{NamedTuple}
    icu_admission_buffer::Vector{NamedTuple}
    discharge_buffer::Vector{NamedTuple}
    death_buffer::Vector{NamedTuple}
    recovery_buffer::Vector{NamedTuple}
    symptom_buffer::Vector{NamedTuple}
    vaccine_buffer::Vector{NamedTuple}
end

"""
    Record(; record_path="results", record_static_data=true)

Create a new `Record`, ensuring the output directory exists.
"""
function Record(; record_path::String="results", record_static_data::Bool=true)
    mkpath(record_path)
    return Record(
        record_path, record_static_data,
        NamedTuple[], NamedTuple[], NamedTuple[], NamedTuple[],
        NamedTuple[], NamedTuple[], NamedTuple[], NamedTuple[]
    )
end

# ---------------------------------------------------------------------------
# Accumulation helpers
# ---------------------------------------------------------------------------

"""Record an infection event."""
function accumulate_infection!(record::Record; kwargs...)
    push!(record.infection_buffer, (; kwargs...))
end

"""Record a hospital admission."""
function accumulate_hospital_admission!(record::Record; kwargs...)
    push!(record.hospital_admission_buffer, (; kwargs...))
end

"""Record an ICU admission."""
function accumulate_icu_admission!(record::Record; kwargs...)
    push!(record.icu_admission_buffer, (; kwargs...))
end

"""Record a hospital discharge."""
function accumulate_discharge!(record::Record; kwargs...)
    push!(record.discharge_buffer, (; kwargs...))
end

"""Record a death."""
function accumulate_death!(record::Record; kwargs...)
    push!(record.death_buffer, (; kwargs...))
end

"""Record a recovery."""
function accumulate_recovery!(record::Record; kwargs...)
    push!(record.recovery_buffer, (; kwargs...))
end

"""Record a symptom-onset event."""
function accumulate_symptom!(record::Record; kwargs...)
    push!(record.symptom_buffer, (; kwargs...))
end

"""Record a vaccination."""
function accumulate_vaccine!(record::Record; kwargs...)
    push!(record.vaccine_buffer, (; kwargs...))
end

# ---------------------------------------------------------------------------
# Flush / write
# ---------------------------------------------------------------------------

"""
    time_step!(record::Record, timestamp)

Write accumulated buffers to HDF5 and clear them.
"""
function time_step!(record::Record, timestamp)
    filepath = joinpath(record.record_path, "records.h5")

    _flush_buffer!(filepath, "infections",          record.infection_buffer,          timestamp)
    _flush_buffer!(filepath, "hospital_admissions",  record.hospital_admission_buffer, timestamp)
    _flush_buffer!(filepath, "icu_admissions",       record.icu_admission_buffer,      timestamp)
    _flush_buffer!(filepath, "discharges",           record.discharge_buffer,          timestamp)
    _flush_buffer!(filepath, "deaths",               record.death_buffer,              timestamp)
    _flush_buffer!(filepath, "recoveries",           record.recovery_buffer,           timestamp)
    _flush_buffer!(filepath, "symptoms",             record.symptom_buffer,            timestamp)
    _flush_buffer!(filepath, "vaccinations",         record.vaccine_buffer,            timestamp)
end

function _flush_buffer!(filepath::String, group_name::String,
                        buffer::Vector{NamedTuple}, timestamp)
    isempty(buffer) && return
    try
        h5open(filepath, isfile(filepath) ? "r+" : "w") do fid
            ts_key = string(timestamp)
            grp = haskey(fid, group_name) ? fid[group_name] : create_group(fid, group_name)
            ts_grp = create_group(grp, ts_key)

            # Extract columns from buffer
            if !isempty(buffer)
                ks = keys(first(buffer))
                for k in ks
                    vals = [nt[k] for nt in buffer]
                    ts_grp[string(k)] = vals
                end
            end
        end
    catch e
        @warn "Record write failed for $group_name" exception=(e, catch_backtrace())
    end
    empty!(buffer)
end

"""
    static_data!(record::Record, world)

Write static population and geography metadata to HDF5.
"""
function static_data!(record::Record, world)
    !record.record_static_data && return
    filepath = joinpath(record.record_path, "records.h5")

    try
        h5open(filepath, isfile(filepath) ? "r+" : "w") do fid
            # Population data
            pop_grp = haskey(fid, "population") ? fid["population"] : create_group(fid, "population")
            if hasproperty(world, :people) && world.people !== nothing
                ids  = Int[p.id for p in world.people]
                ages = Int[p.age for p in world.people]
                sexs = Char[p.sex for p in world.people]
                pop_grp["id"]  = ids
                pop_grp["age"] = ages
                pop_grp["sex"] = Int.(sexs)
            end

            # Area metadata
            if hasproperty(world, :areas) && world.areas !== nothing
                area_grp = haskey(fid, "areas") ? fid["areas"] : create_group(fid, "areas")
                area_ids   = Int[]
                area_names = String[]
                try
                    for a in world.areas
                        push!(area_ids, a.id)
                        push!(area_names, a.name)
                    end
                    area_grp["id"]   = area_ids
                    area_grp["name"] = area_names
                catch
                end
            end
        end
    catch e
        @warn "Static data write failed: $e"
    end
end

function Base.show(io::IO, r::Record)
    n_buf = sum(length, [
        r.infection_buffer, r.hospital_admission_buffer,
        r.icu_admission_buffer, r.discharge_buffer,
        r.death_buffer, r.recovery_buffer,
        r.symptom_buffer, r.vaccine_buffer
    ])
    print(io, "Record(path=\"$(r.record_path)\", buffered=$n_buf)")
end
