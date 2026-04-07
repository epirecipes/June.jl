# ============================================================================
# Subgroup parameter configuration
#
# Defines how each group spec partitions people into subgroups — either
# by age bins or by discrete category labels.
#
# Included inside `module June`; no sub-module wrapper.
# ============================================================================

# ── Age-threshold constants ──────────────────────────────────────────────

const AGE_YOUNG_ADULT = 18
const AGE_ADULT       = 18
const AGE_OLD_ADULT   = 65

# ── Type ─────────────────────────────────────────────────────────────────

"""
    SubgroupParams

Describes the subgroup structure for one group spec.

* `labels` — human-readable names for each subgroup slot
* `subgroup_type` — `:age` (continuous bins) or `:discrete` (named categories)
* `bins` — for `:age`: edge values `[0, 18, 65, 100]`;
            for `:discrete`: the same strings as `labels`
"""
struct SubgroupParams
    labels::Vector{String}
    subgroup_type::Symbol        # :age or :discrete
    bins::Vector{Any}            # age edges or category names
end

# ── Excel-style column name generator ────────────────────────────────────

"""Generate Excel-style column labels: A, B, …, Z, AA, AB, …"""
function _excel_cols(n::Int)
    labels = String[]
    for i in 1:n
        s = ""
        val = i
        while val > 0
            val, rem = divrem(val - 1, 26)
            s = string(Char('A' + rem)) * s
        end
        push!(labels, s)
    end
    return labels
end

# ── Defaults per spec ────────────────────────────────────────────────────

"""
    get_default_subgroup_params(spec::String) → SubgroupParams

Return the built-in default subgroup configuration for the given group
spec string.
"""
function get_default_subgroup_params(spec::String)
    if spec in ("pub", "grocery", "cinema", "gym")
        bins = Any[0, 100]
        labels = _excel_cols(length(bins) - 1)
        return SubgroupParams(labels, :age, bins)

    elseif spec == "household"
        cats = ["kids", "young_adults", "adults", "old_adults"]
        return SubgroupParams(cats, :discrete, Any[c for c in cats])

    elseif spec == "school"
        cats = ["teachers", "students"]
        return SubgroupParams(cats, :discrete, Any[c for c in cats])

    elseif spec == "company"
        cats = ["workers"]
        return SubgroupParams(cats, :discrete, Any[c for c in cats])

    elseif spec == "hospital"
        cats = ["workers", "patients", "icu_patients"]
        return SubgroupParams(cats, :discrete, Any[c for c in cats])

    elseif spec == "care_home"
        cats = ["workers", "residents", "visitors"]
        return SubgroupParams(cats, :discrete, Any[c for c in cats])

    elseif spec == "university"
        cats = ["1", "2", "3", "4", "5"]
        return SubgroupParams(cats, :discrete, Any[c for c in cats])

    elseif spec in ("city_transport", "inter_city_transport")
        bins = Any[0, 100]
        labels = _excel_cols(length(bins) - 1)
        return SubgroupParams(labels, :age, bins)

    else
        # Fallback: single age bin covering all ages
        bins = Any[0, 100]
        labels = _excel_cols(1)
        return SubgroupParams(labels, :age, bins)
    end
end

# ── YAML loading ─────────────────────────────────────────────────────────

"""
    load_subgroup_params(config_path::String) → Dict{String, SubgroupParams}

Read an interaction YAML file and return a dictionary mapping each spec
to its `SubgroupParams`.  Expected YAML structure:

```yaml
contact_matrices:
  household:
    bins: ["kids", "young_adults", "adults", "old_adults"]
    type: Discrete
  pub:
    bins: [0, 18, 65, 100]
    type: Age
```
"""
function load_subgroup_params(config_path::String)
    cfg = YAML.load_file(config_path)
    matrices = get(cfg, "contact_matrices", cfg)
    result = Dict{String, SubgroupParams}()
    for (spec, params) in matrices
        bins_raw = get(params, "bins", Any[0, 100])
        type_raw = lowercase(get(params, "type", "age"))
        stype = type_raw == "discrete" ? :discrete : :age

        bins = Any[b for b in bins_raw]
        if stype == :age
            labels = _excel_cols(max(length(bins) - 1, 1))
        else
            labels = [string(b) for b in bins]
        end
        result[spec] = SubgroupParams(labels, stype, bins)
    end
    return result
end

# ── Subgroup index lookup ────────────────────────────────────────────────

"""
    get_subgroup_index(params::SubgroupParams, age::Int) → Int

For age-based params, return the 1-based bin index that `age` falls into.
For discrete params, return 1 (caller is responsible for mapping discrete
categories to an index).
"""
function get_subgroup_index(params::SubgroupParams, age::Int)
    if params.subgroup_type == :age
        for i in 1:(length(params.bins) - 1)
            lo = params.bins[i]
            hi = params.bins[i + 1]
            if age >= lo && age < hi
                return i
            end
        end
        # If age >= last upper bound, place in last bin
        return max(length(params.bins) - 1, 1)
    else
        # Discrete: caller decides the index; default to 1
        return 1
    end
end

"""
    n_subgroups(params::SubgroupParams) → Int

Number of subgroup slots described by these params.
"""
function n_subgroups(params::SubgroupParams)
    if params.subgroup_type == :age
        return max(length(params.bins) - 1, 1)
    else
        return length(params.labels)
    end
end

# ── Legacy helper ────────────────────────────────────────────────────────

"""
    make_subgroups(group, n::Int) → Vector{Subgroup}

Create `n` subgroups owned by `group`, with 1-based subgroup types.
"""
function make_subgroups(group, n::Int)
    return [Subgroup(group, i) for i in 1:n]
end
