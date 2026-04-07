# ============================================================================
# Transmission — infectiousness profiles
#
# Included inside `module June`; no sub-module wrapper.
# Assumes Distributions (Gamma, Normal, LogNormal) is already imported.
# ============================================================================

# ---------------------------------------------------------------------------
# Abstract type
# ---------------------------------------------------------------------------
abstract type AbstractTransmission end

# ---------------------------------------------------------------------------
# Constant transmission
# ---------------------------------------------------------------------------
mutable struct TransmissionConstant <: AbstractTransmission
    probability::Float64
end

function update_infection_probability!(t::TransmissionConstant, time_from_infection::Float64)
    return nothing
end

# ---------------------------------------------------------------------------
# Gamma-shaped transmission
# ---------------------------------------------------------------------------

"""Fast inline Gamma PDF: x^(k-1) * exp(-x/θ) / (θ^k * Γ(k))"""
@inline function _gamma_pdf(x::Float64, shape::Float64, scale::Float64)
    x <= 0.0 && return 0.0
    return exp((shape - 1.0) * log(x) - x / scale - shape * log(scale) - loggamma(shape))
end

mutable struct TransmissionGamma <: AbstractTransmission
    max_infectiousness::Float64
    shape::Float64
    rate::Float64
    shift::Float64
    norm::Float64
    probability::Float64
end

function TransmissionGamma(max_infectiousness::Float64, shape::Float64, rate::Float64, shift::Float64)
    scale = 1.0 / rate
    time_at_max = (shape - 1.0) * scale + shift
    norm = max_infectiousness / _gamma_pdf(time_at_max - shift, shape, scale)
    return TransmissionGamma(max_infectiousness, shape, rate, shift, norm, 0.0)
end

function update_infection_probability!(t::TransmissionGamma, time_from_infection::Float64)
    if time_from_infection > t.shift
        t.probability = t.norm * _gamma_pdf(time_from_infection - t.shift, t.shape, 1.0 / t.rate)
    else
        t.probability = 0.0
    end
    return nothing
end

# ---------------------------------------------------------------------------
# X^N * Exp(-X/alpha) transmission
# ---------------------------------------------------------------------------
mutable struct TransmissionXNExp <: AbstractTransmission
    max_probability::Float64
    time_first_infectious::Float64
    norm_time::Float64
    n::Float64
    alpha::Float64
    norm::Float64
    probability::Float64
end

function TransmissionXNExp(max_probability::Float64, time_first_infectious::Float64,
                           norm_time::Float64, n::Float64, alpha::Float64)
    x_max = n * alpha
    norm = max_probability / (x_max^n * exp(-x_max / alpha))
    return TransmissionXNExp(max_probability, time_first_infectious, norm_time, n, alpha, norm, 0.0)
end

function update_infection_probability!(t::TransmissionXNExp, time_from_infection::Float64)
    x = (time_from_infection - t.time_first_infectious) / t.norm_time
    if x <= 0.0
        t.probability = 0.0
    else
        t.probability = t.norm * x^t.n * exp(-x / t.alpha)
    end
    return nothing
end

# ---------------------------------------------------------------------------
# Parameter sampling helper
# ---------------------------------------------------------------------------

"""
    sample_parameter(param)

Sample a numeric parameter from a config value. If `param` is a number it is
returned directly; if it is a `Dict` with a `"type"` key the corresponding
distribution is sampled.
"""
function sample_parameter(param)
    if isa(param, Number)
        return Float64(param)
    elseif isa(param, Dict)
        dist_type = get(param, "type", "")
        if dist_type == "normal"
            return rand(Normal(Float64(param["mean"]), Float64(param["std"])))
        elseif dist_type == "lognormal"
            return rand(LogNormal(Float64(param["meanlog"]), Float64(param["sdlog"])))
        elseif dist_type == "uniform"
            return rand(Uniform(Float64(param["low"]), Float64(param["high"])))
        else
            throw(ArgumentError("Unknown distribution type: $dist_type"))
        end
    end
    return Float64(param)
end

# ---------------------------------------------------------------------------
# Config-driven factory
# ---------------------------------------------------------------------------

"""
    transmission_from_config(config::Dict; time_to_symptoms_onset::Float64=0.0)

Create a transmission profile from a YAML-like config dictionary.
"""
function transmission_from_config(config::Dict; time_to_symptoms_onset::Float64=0.0)
    type = config["type"]
    if type == "TransmissionGamma" || type == "gamma"
        shape = sample_parameter(config["shape"])
        rate = sample_parameter(config["rate"])
        shift = sample_parameter(config["shift"]) + time_to_symptoms_onset
        max_inf = sample_parameter(config["max_infectiousness"])
        return TransmissionGamma(max_inf, shape, rate, shift)
    elseif type == "TransmissionXNExp" || type == "xnexp"
        max_prob = sample_parameter(config["max_probability"])
        time_first = sample_parameter(get(config, "time_first_infectious", 0.0))
        norm_time = sample_parameter(config["norm_time"])
        n = sample_parameter(config["n"])
        alpha = sample_parameter(config["alpha"])
        return TransmissionXNExp(max_prob, time_first + time_to_symptoms_onset, norm_time, n, alpha)
    elseif type == "TransmissionConstant" || type == "constant"
        return TransmissionConstant(Float64(config["probability"]))
    else
        throw(ArgumentError("Unknown transmission type: $type"))
    end
end
